from Crypto.Signature import eddsa
from Crypto.PublicKey import ECC

body = bytes.fromhex("f16ff19f62966867818a62a43d7e8a26f698e187f30aafe162a48657615f65d12343a68accd8596768b10a8e0767d7cf80387d42c640482add1772d98b1b91c53372e156767f40c4c10c9ac34c6f1621a54e2df6078298d2bb")
pubkey = bytes.fromhex("e7043835f45f3a60b00cb1315600d791006d58ced32368d300affe69839f0dd3")
sig = bytes.fromhex("c47046aa86c17b3d59f8865556949edb7bf34f156d942641c8b65e70f664eb3091d382edaa14f38da422372dc81094cb2acb281b62ddf91a1300033dfd8b3903")

privkey = "-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIHTI9n0ipGCLchGSUfsDVuzdxATVSWdCZckhqRLkZviD\n-----END PRIVATE KEY-----"
privkey2 = ECC.import_key(privkey)

# eddsa.import_private_key

# print(privkey2.public_key().export_key())

# pubkey2 = eddsa.import_public_key(pubkey)

# eddsa.new(pubkey2, "rfc8032").verify(body, sig)