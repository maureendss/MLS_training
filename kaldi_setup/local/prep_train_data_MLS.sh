#!/usr/bin/env bash

# Copyright 2014  Vassil Panayotov
#           2014  Johns Hopkins University (author: Daniel Povey)
#           2021  Xuechen LIU
# Apache 2.0

run_lm=False
. ./utils/parse_options.sh

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <src-segments> <src_mls_set> <dst-dir>"
  echo "e.g.: $0 ~/projects/data_preparation/MLS/train_french_100h.csv ~/data/speech/MLS/mls_french/train data/MLS/french_tr-100h"
  exit 1
fi

og_segments=$1
MLS_dir=$2
tgt_dir=$3
lm_dir=$4

mkdir -p $tgt_dir

#1-Create_transcripts





if [ -f $tgt_dir/text ]; then
    echo "$tgt_dir/text already exists, not recomputing it."

else
    echo "Creating text"
    grep -f <(cut -d ',' -f2 $og_segments) $MLS_dir/transcripts.txt |  awk -F'_' '{print $1"-"$2"-"$3}' | sort > $tgt_dir/text

fi


if [ -f $tgt_dir/spk2utt ] && [ -f $tgt_dir/utt2spk ]; then
    echo "$tgt_dir/spk2utt and $tgt_dir/utt2spk already exist, not recomputing them."

else
    
    echo "Creating utt2spk"
    cut -d',' -f 2 $og_segments | awk -F'_' '{print $1"-"$2"-"$3" "$1}' | sort > $tgt_dir/utt2spk
    utils/utt2spk_to_spk2utt.pl $tgt_dir/utt2spk > $tgt_dir/spk2utt
fi


if [ ! -f $tgt_dir/wav.scp ]; then
    echo "Creating $tgt_dir/wav.scp"

    cut -d' ' -f 1 $tgt_dir/utt2spk | awk -v VARIABLE=$MLS_dir -F'-' '{print $1"-"$2"-"$3" sox "VARIABLE"/audio/"$1"/"$2"/"$1"_"$2"_"$3".flac -t wav -r 16000 - |"}' | sort >  $tgt_dir/wav.scp
     
else
    echo "$tgt_dir/wav.scp already exists, not recomputing it"
fi

mkdir -p $tgt_dir/local/lang

if  [ ! -f $tgt_dir/local/lang/lexicon.txt ]; then
    if [ "$lang" == "french" ]; then
        wget -O $tgt_dir/local/lang/lexicon.txt https://raw.githubusercontent.com/openpaas-ng/openpaas-sp5-kaldi-french-v1/master/lexicon/lexicon
    elif [ "$lang" == "english" ]; then
        wget -O $tgt_dir/local/lang/lexicon_uncleaned.txt http://svn.code.sf.net/p/cmusphinx/code/trunk/cmudict/cmudict-0.7b

        #below we check the cmu and also do the folding of AH0 -> AH0 and AH1/2 -> AH
        perl local/cmu_make_baseform_withfolding.pl $tgt_dir/local/lang/lexicon_uncleaned.txt /dev/stdout | sed -e 's:^\([^\s(]\+\)([0-9]\+)\(\s\+\)\(.*\):\1\2\3:' | tr '[A-Z]' '[a-z]' > $tgt_dir/local/lang/lexicon.txt  

        # here we do the cleaning based on CMU + folding ! 
    fi

fi


if [ ! -f $tgt_dir/local/lang/nonsilence_phones.txt ]; then
    if [ "$lang" == "french" ]; then
    cut -d ' ' -f 2- $tgt_dir/local/lang/lexicon.txt | sed 's/ /\n/g' | sed '/^[[:space:]]*$/d' | sort -u > $tgt_dir/local/lang/nonsilence_phones.txt 

    else #here cut using tab 
        cut -d$'\t' -f 2- $tgt_dir/local/lang/lexicon.txt | sed 's/ /\n/g' | sed '/^[[:space:]]*$/d' | sort -u > $tgt_dir/local/lang/nonsilence_phones.txt
    fi
    echo 'SIL' > $tgt_dir/local/lang/silence_phones.txt
    echo '<unk>' >> $tgt_dir/local/lang/silence_phones.txt
    echo '<unk> <unk>' >> $tgt_dir/local/lang/lexicon.txt 
    echo 'SIL' > $tgt_dir/local/lang/optional_silence.txt
fi

if [ ! -d $tgt_dir/lang ]; then
    mkdir -p $tgt_dir/lang

    utils/prepare_lang.sh $tgt_dir/local/lang '<unk>' $tgt_dir/local/ $tgt_dir/lang
fi

#Is this useful? 
if [ ! -f $tgt_dir/lang_test_phones ] && [ "$run_lm" == "True" ]; then
    lm=data/MLS_LM_phones/${lang}.arpa
    test=$tgt_dir/lang_test_lm_phones
    mkdir -p $test
    cp -r $tgt_dir/lang/* $tgt_dir/lang_test_lm_3g
    arpa2fst --disambig-symbol=#0 --read-symbol-table=$test/words.txt $lm $test/G.fst

#    $test/G.fst
    
fi



#Is this useful? 
if [ ! -f $tgt_dir/lang_test_lm_3g ] && [ "$run_lm" == "True" ]; then

    lm_3g=$lm_dir/3-gram_lm.arpa
    test=$tgt_dir/lang_test_lm_3g
    mkdir -p $test
    cp -r $tgt_dir/lang/* $tgt_dir/lang_test_lm_3g
    arpa2fst --disambig-symbol=#0 --read-symbol-table=$test/words.txt $lm_3g $test/G.fst
    arpa2fst --keep_isymbols=false--keep_osymbols=false  --read-symbol-table=$test/words.txt $lm_3g $test/G.fst
#    $test/G.fst
    
fi


