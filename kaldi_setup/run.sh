#!/usr/bin/env bash

#used https://github.com/kaldi-asr/kaldi/blob/master/egs/librispeech/s5/run.sh
#skipping recomputing pronunciations
#chain is from librivox recipe


mfccdir=mfcc
stage=2
tdnn_stage=0

stage=0
train=true   # set to false to disable the training-related scripts
             # note: you probably only want to set --train false if you
             # are using at least --stage 1.
decode=true  # set to false to disable the decoding-related scripts.



MLS_data=~/data/speech/MLS
lang=english

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
. ./path.sh
           ## This relates to the queue.
. utils/parse_options.sh  # e.g. this parses the --stage option if supplied.

tr_data=MLS-${lang}_tr-100h
ts_data=CV-${lang}_ts-10h

# you might not want to do this for interactive shells.
set -e

echo lang: $lang 


if [ $stage -le 1 ]; then
    train_segments=~/projects/data_preparation/MLS/train_${lang}_100h.csv
    local/prep_train_data_MLS.sh $train_segments $MLS_data/mls_$lang/train data/$tr_data $MLS_data/mls_lm_$lang

fi


#if [ $stage -le 2 ]; then

    #prepre test data . + LM
    #train_segments="~/projects/data_preparation/MLS/train_french_100h.csv"
    #local/prep_test_data_CV.sh $train_segments $MLS_data/mls_$lang/train/transcripts.txt $tr_data $MLS_data/mls_lm_$lang

    
    #do same for test
    #USE MLS_LM for test as test time
#fi



if [ $stage -le 3 ]; then
  for part in $tr_data $ts_data; do
    steps/make_mfcc.sh --cmd "$train_cmd" --nj 40 data/$part exp/make_mfcc/$part $mfccdir
    steps/compute_cmvn_stats.sh data/$part exp/make_mfcc/$part $mfccdir
  done
fi



if [ $stage -le 7 ]; then
  # Make some small data subsets for early system-build stages.  Note, there are 29k
  # utterances in the train_clean_100 directory which has 100 hours of data.
  # For the monophone stages we select the shortest utterances, which should make it
  # easier to align the data from a flat start.

  utils/subset_data_dir.sh --shortest data/${tr_data} 2000 data/${tr_data}_2kshort
  utils/subset_data_dir.sh data/${tr_data} 5000 data/${tr_data}_5k
  utils/subset_data_dir.sh data/${tr_data} 10000 data/${tr_data}_10k
fi

if [ $stage -le 8 ]; then
  # train a monophone system
  steps/train_mono.sh --boost-silence 1.25 --nj 20 --cmd "$train_cmd" \
                      data/${tr_data}_2kshort data/${tr_data}/lang exp/$lang/mono/
fi

if [ $stage -le 9 ]; then
  steps/align_si.sh --boost-silence 1.25 --nj 10 --cmd "$train_cmd" \
                    data/${tr_data}_5k data/${tr_data}/lang exp/$lang/mono exp/$lang/mono_ali_5k

  # train a first delta + delta-delta triphone system on a subset of 5000 utterances
  steps/train_deltas.sh --boost-silence 1.25 --cmd "$train_cmd" \
                        2000 10000 data/${tr_data}_5k data/${tr_data}/lang exp/$lang/mono_ali_5k exp/$lang/tri1
fi

if [ $stage -le 10 ]; then
  steps/align_si.sh --nj 10 --cmd "$train_cmd" \
                    data/${tr_data}_10k data/${tr_data}/lang exp/$lang/tri1 exp/$lang/tri1_ali_10k


  # train an LDA+MLLT system.
  steps/train_lda_mllt.sh --cmd "$train_cmd" \
                          --splice-opts "--left-context=3 --right-context=3" 2500 15000 \
                          data/${tr_data}_10k data/${tr_data}/lang exp/$lang/tri1_ali_10k exp/$lang/tri2b
fi

if [ $stage -le 11 ]; then
  # Align a 10k utts subset using the tri2b model
  steps/align_si.sh  --nj 10 --cmd "$train_cmd" --use-graphs true \
                     data/${tr_data}_10k data/${tr_data}/lang \
                     exp/$lang/tri2b exp/$lang/tri2b_ali_10k

  # Train tri3b, which is LDA+MLLT+SAT on 10k utts
  steps/train_sat.sh --cmd "$train_cmd" 2500 15000 \
                     data/${tr_data}_10k data/${tr_data}/lang \
                     exp/$lang/tri2b_ali_10k exp/$lang/tri3b ;

fi

if [ $stage -le 12 ]; then
    # align the entire train_clean_100 subset using the tri3b model
    steps/align_fmllr.sh --nj 20 --cmd "$train_cmd" \
                         data/${tr_data} data/${tr_data}/lang \
                         exp/$lang/tri3b exp/$lang/tri3b_ali

    # creata a phone bigram LM using the alignments phones.
    if [ ! -d data/${tr_data}/lang_phone_bg ]; then
        local/make_phone_bigram_lang_nounk.sh data/$tr_data/lang exp/$lang/tri3b_ali data/${tr_data}/lang_phone_bg;
    fi
    
    # train another LDA+MLLT+SAT system on the entire 100 hour subset
    steps/train_sat.sh  --cmd "$train_cmd" 4200 40000 \
                        data/${tr_data} data/${tr_data}/lang \
                        exp/$lang/tri3b_ali exp/$lang/tri4b
fi

if [ $stage -eq 13 ] && [ "$decode" == true] ; then
 utils/mkgraph.sh data/${tr_data}/lang_phone_bg \
                   exp/$lang/tri4b  exp/$lang/tri4b/graph_phone_bg   

    steps/decode_fmllr.sh --nj 20 --cmd "$decode_cmd" exp/$lang/tri4b/graph_phone_bg data/$ts_dir exp/$lang/tri4b/decode_phone_bg_$ts_dir
fi


if [ $stage -eq 20 ]; then
  # train and test nnet3 tdnn models on the entire data with data-cleaning.
    local/chain/run_tdnn.sh --train_set $tr_data --gmm "$lang/tri4b" --nnet3_affix "_$lang" --test_set $ts_data --stage $tdnn_stage
    
fi

if [ $stage -eq 201 ]; then
  # train and test nnet3 tdnn models on the entire data with data-cleaning.
    local/chain/run_tdnn.sh --train_set $tr_data --gmm "$lang/tri4b" --nnet3_affix "_$lang" --affix "1d_15ep" --epochs 15 --stage $tdnn_stage --test_set $ts_data
    
fi

if [ $stage -eq 200 ]; then
  # train and test nnet3 tdnn models on the entire data with data-cleaning.
    local/chain/run_tdnn_ami-config.sh  --train_set $tr_data --gmm "$lang/tri4b" --nnet3_affix "_$lang"
    
fi
