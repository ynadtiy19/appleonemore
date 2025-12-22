class Constants {
  // LibSQL
  static const String dbUrl =
      "libsql://production-db-aws-us-west-2-27f0534851-big-vanadyl-globe.turso.io";
  static const String dbToken =
      "eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE3NjYwNzcxNTIsInAiOnsicnciOnsibnMiOlsiY2ViZDlhMTItOWVlNS00ZmFjLTljZTEtNTFmZmU1MTFhYWQ0Il19fSwicmlkIjoiZjM4MzMwYmEtMmI5MC00ODI5LThkOTItODIyNzhjNGNlMTk0In0.MbiA2eRIb5qGgAvbp6E7tvsqeaRIiObQu4dKeyqNGsikij52Gq1JFnBKonoggosukBEtr7XRrE4L8fTapqs-BQ";

  static const String msgDbUrl =
      "libsql://production-db-aws-us-west-2-27f0534851-disloyal-wallaby-globe.turso.io";
  static const String msgDbToken =
      "eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJpYXQiOjE3NjYzMzQwMzcsInAiOnsicnciOnsibnMiOlsiNzg2NWEwZTctOTJjZS00Zjc5LTlkMzMtZmU0YzVhYmQ1ZTA0Il19fSwicmlkIjoiMzg4MzEwYmQtYzUyNS00ZDg2LWEzNjktOGU2NWUxODcwYWNiIn0.YXc9TnFpVg8tnvuXq0CMzp_amE996QWs51Z9h0UQjuJSKRpThUQ_rrc5HgIlsxW6FNKEw3kEHKoSiY2mUFcYAA";
  // Cloudinary
  static const String cloudinaryUrl =
      'https://api.cloudinary.com/v1_1/ddgzciyug/image/upload';
  static const String cloudinaryPreset = 'supplyuuu';

  // CometChat Translation
  static const String translationUrl =
      'https://message-translation-in.cc-cluster-2.io/v2/translate';
  static const Map<String, String> translationHeaders = {
    'accept': ' application/json',
    'accept-language': ' zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
    'appid': '267879a77f4b29cd',
    'authorization':
        'Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImtpZCI6ImNjcHJvX2p3dF9yczI1Nl9rZXkxIn0.eyJpc3MiOiJodHRwczovL2FwaWNsaWVudC1pbi5jb21ldGNoYXQuaW8iLCJhdWQiOiJydGMtaW4uY29tZXRjaGF0LmlvIiwiaWF0IjoxNzY1ODE1ODU2LCJzdWIiOiJbMjY3ODc5YTc3ZjRiMjljZF1kZW1vXzE3NjU3ODQ5NDAzMjhfMjkiLCJuYmYiOjE3NjU4MTIyNTYsImV4cCI6MTc3MTA3NTg1NiwiZGF0YSI6eyJhcHBJZCI6IjI2Nzg3OWE3N2Y0YjI5Y2QiLCJyZWdpb24iOiJpbiIsImF1dGhUb2tlbiI6ImRlbW9fMTc2NTc4NDk0MDMyOF8yOV8xNzY1Nzg2NDY5YTU0YmEwYWVjYWRiNjljZmNjZDk5MTQ1ZmIzM2FiIiwidXNlciI6eyJ1aWQiOiJkZW1vXzE3NjU3ODQ5NDAzMjhfMjkiLCJuYW1lIjoiUmVuZWUgVG9ycCIsImF2YXRhciI6Imh0dHBzOi8vZGF0YS1pbi5jb21ldGNoYXQuaW8vMjY3ODc5YTc3ZjRiMjljZC9hdmF0YXJzL2RlbW9fMTc2NTc4NDk0MDMyOF8yOS53ZWJwIiwic3RhdHVzIjoib2ZmbGluZSIsInJvbGUiOiJkZW1vIn19fQ.hVWd-T2iAIYNux1vxmzM7m5C5W7jFNzEn-69qJOspr8m17qqu7NLC_onNzwFIcIrq7bM3U8fJuTOCYwSPf7ZL-U80M6Xzj0OSxoao3NhbC-n9cKXQp4pHpqrNB2LdYuxrWZkdjiQSIwo16rqIIsojy2MFwT4rYNpHEBvlRvha6g',
    'authtoken':
        'demo_1765784940328_29_1765786469a54ba0aecadb69cfccd99145fb33ab',
    'cache-control': ' no-cache',
    'chatapiversion': ' v3.0',
    'content-type': ' application/json',
    'origin': ' https://app.cometchat.com',
  };
}
