#!/bin/sh

set -x

OUTPUT_DIR="output"
mkdir -p ${OUTPUT_DIR}

PYTHON="python"  # Path to the python installed.
GIT='git'  # Path to the git installed.


###############################################################
# Download the PITT Ads dataset.
###############################################################
if [ ! -f "data/README.txt" ]; then
  FILEID="1axqdkK5TVHlnkkZjfb12Dv2IusTlDIxw"
  confirm_id=`wget --quiet \
    --save-cookies /tmp/cookies.txt \
    --keep-session-cookies \
    --no-check-certificate \
    "https://docs.google.com/uc?export=download&id=$FILEID" \
    -O- | sed -rn 's/.*confirm=([0-9A-Za-z_]+).*/\1\n/p'`
  
  wget --load-cookies /tmp/cookies.txt \
    "https://docs.google.com/uc?export=download&confirm=${confirm_id}&id=$FILEID"\
    -O "data/test-set.zip" \
    || exit -1
  
  cd "data" && unzip -q "test-set.zip" || exit -1
  cd -
  
  rm -rf /tmp/cookies.txt
  rm "data/test-set.zip"
fi

###############################################################
# Clone the repository of tensorflow models.
# We need:
#   1) "slim" for inception model;
#   2) "object_detection" since we use some easi-to-use functions.
#         also the output/symbol_box_*.json is generated by this library.
###############################################################
$GIT clone "https://github.com/tensorflow/models.git" "tensorflow_models"

export PYTHONPATH="`pwd`/tensorflow_models/research:$PYTHONPATH"
export PYTHONPATH="`pwd`/tensorflow_models/research/slim:$PYTHONPATH"

cd "tensorflow_models/research" \
  && protoc object_detection/protos/*.proto --python_out=. \
  && cd - || exit -1

test -d "object_detection" \
  || ln -s "tensorflow_models/research/object_detection" . \
  || exit -1

###############################################################
# Download the GloVe model and the Inception V4 model.
###############################################################
mkdir -p "zoo"
if [ ! -f "zoo/glove.6B.200d.txt" ]; then
  wget -O "zoo/glove.6B.zip" \
    "http://nlp.stanford.edu/data/glove.6B.zip" \
    || exit -1

  cd "zoo" && unzip -q "glove.6B.zip" || exit -1
  rm "glove.6B.zip"
  cd -
fi

if [ ! -f "zoo/inception_v4.ckpt" ]; then
  wget -O "zoo/inception_v4_2016_09_09.tar.gz" \
    "http://download.tensorflow.org/models/inception_v4_2016_09_09.tar.gz" \
    || exit -1
  cd "zoo" && tar xzvf "inception_v4_2016_09_09.tar.gz" || exit -1
  rm "inception_v4_2016_09_09.tar.gz"
  cd -
fi

###############################################################
# Prepare the symbol data, using the 53-symbols ontology.
###############################################################
$PYTHON "tools/prepare_symbol_data.py" \
  --symbol_raw_annot_path="data/train/Symbols_train.json" \
  --output_json_path="output/symbol_train.json" \
  || exit -1

$PYTHON "tools/prepare_symbol_data.py" \
  --symbol_raw_annot_path="data/test/Symbols_test.json" \
  --output_json_path="output/symbol_test.json" \
  || exit -1

###############################################################
# Prepare the vocabulary and initial embedding matrix for:
#   1) Ads action-reason annotations;
#   2) Densecap annotations;
#   3) Symbol annotations.
###############################################################

# 1) Ads action-reason annotations;
$PYTHON "tools/prepare_action_reason_vocab.py" \
  --min_count=1 || exit -1
$PYTHON "tools/prepare_word_embedding.py" \
  --vocab_path="output/action_reason_vocab.txt" \
  --output_emb_path="output/action_reason_vocab_200d.npy" \
  --output_vocab_path="output/action_reason_vocab_200d.txt" \
  || exit -1

# 2) Densecap annotations;
$PYTHON "tools/prepare_densecap_vocab.py" \
  --min_count=1 || exit -1
$PYTHON "tools/prepare_word_embedding.py" \
    --vocab_path="output/densecap_vocab.txt" \
    --output_emb_path="output/densecap_vocab_200d.npy" \
    --output_vocab_path="output/densecap_vocab_200d.txt" \
    || exit -1

# 3) Symbol annotations.
$PYTHON "tools/prepare_symbol_list.py" \
  --symbol_cluster_path="data/additional/clustered_symbol_list.json" \
  || exit -1
$PYTHON "tools/prepare_word_embedding.py" \
  --vocab_path="output/symbol_vocab.txt" \
  --output_emb_path="output/symbol_vocab_200d.npy" \
  --output_vocab_path="output/symbol_vocab_200d.txt" \
  || exit -1

###############################################################
# Extract Inception V4 features.
# Warning: this will cost a long time to run!!!
###############################################################
export CUDA_VISIBLE_DEVICES=1
$PYTHON "tools/prepare_img_features.py" \
  --action_reason_annot_path="data/train/QA_Combined_Action_Reason_train.json" \
  --image_dir="data/train_images/" \
  --output_feature_path="output/img_features_train.npy" \
  || exit -1

$PYTHON "tools/prepare_img_features.py" \
  --action_reason_annot_path="data/test/QA_Combined_Action_Reason_test.json" \
  --image_dir="data/test_images/" \
  --output_feature_path="output/img_features_test.npy" \
  || exit -1

$PYTHON "tools/prepare_roi_features.py" \
  --bounding_box_json="output/symbol_box_train.json" \
  --image_dir="data/train_images/" \
  --output_feature_path="output/roi_features_train.npy" \
  || exit -1

$PYTHON "tools/prepare_roi_features.py" \
  --bounding_box_json="output/symbol_box_test.json" \
  --image_dir="data/test_images/" \
  --output_feature_path="output/roi_features_test.npy" \
  || exit -1

$PYTHON "tools/prepare_roi_features.py" \
  --bounding_box_json="output/densecap_train.json" \
  --image_dir="data/train_images/" \
  --output_feature_path="output/densecap_roi_features_train.npy" \
  || exit -1

$PYTHON "tools/prepare_roi_features.py" \
  --bounding_box_json="output/densecap_test.json" \
  --image_dir="data/test_images/" \
  --output_feature_path="output/densecap_roi_features_test.npy" \
  || exit -1

exit 0
