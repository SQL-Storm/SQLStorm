-- {"query": "57006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 1543} 


WITH UserActivity AS (
   SELECT
       UserId,
       COUNT(*) AS TotalPosts,
       MAX(CreationDate) AS LastPostDate,
       SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
       SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers
   FROM
       Posts
   GROUP BY
       UserId
),

ReputationData AS (
   SELECT
       Users.Id AS UserId,
       Reputation,
       CreationDate AS UserCreationDate,
       LastAccessDate,
      UA.TotalPosts,
       UA.LastPostDate,
       UA.TotalQuestions,
       UA.TotalAnswers
   FROM
       Users
   JOIN
       UserActivity UA ON Users.Id = UA.UserId
   WHERE
       Reputation > 1000
),

ActiveUsers AS (
   SELECT
       RD.UserId,
       Reputation,
       UserCreationDate,
       LastAccessDate,
       TotalPosts,
       LastPostDate,
       TotalQuestions,
       TotalAnswers,
       DATEDIFF(day, LastAccessDate,  NOW())<=8 AS active_in_past_week,
       DATEDIFF(day, LastPostDate,  NOW())<=15 AS posted_in_last_15_days
   FROM
       ReputationData RD
),

PostMetrics AS (
   SELECT
       P.Id AS PostId,
       P.PostTypeId,
       P.CreationDate,
       P.Score,
       P.ViewCount,
       P.AnswerCount,
       P.CommentCount,
       P.OwnerUserId,
       P.Title,
       U.DisplayName AS OwnerDisplayName,
       U.Reputation AS OwnerReputation,
       C.Id as CommentId, C.Score AS CommentScore, C.UserId AS CommentUserId, C.CreationDate AS CommentCreationDate, C.UserDisplayName AS CommentUserDisplayName
   FROM
       Posts P
   JOIN
       Comments C ON P.Id = C.PostId
   LEFT JOIN
       Users U ON P.OwnerUserId = U.Id
   WHERE
       P.PostTypeId IN (1, 2)
),

PopularPosts AS (
   SELECT
       PostId,
       PostTypeId,
       CreationDate,
       Score,
       ViewCount,
       AnswerCount,
       CommentCount,
       OwnerUserId,
       Title,
       OwnerDisplayName,
       OwnerReputation,
       CommentId,CommentScore,CommentUserId,CommentCreationDate,CommentUserDisplayName,
       ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY CommentScore DESC) AS CommentRank
   FROM
       PostMetrics
),
 TopTags AS (
  SELECT
      T.Id AS TagId,
      T.TagName,
      T.Count,
      P.Id AS RelatedPostId,
      P.Title AS RelatedPostTitle,
      P.CreationDate,
      P.Score AS RelatedPostScore,
      P.ViewCount AS RelatedPostViewCount,
      P.AnswerCount AS RelatedPostAnswerCount,
      P.CommentCount AS RelatedPostCommentCount
  FROM
      Tags T
  JOIN
       Posts P ON T.ExcerptPostId = P.Id
  WHERE
      T.Count > 1000
),
VotingPatterns AS (
   SELECT
       V.PostId,
       V.VoteTypeId,
       V.UserId AS VoterId,
       V.CreationDate AS VoteDate,
       P.Title AS PostTitle,
       P.PostTypeId,
       P.OwnerUserId,
       P.Score AS PostScore,
       COUNT(*) AS VoteCount,
       SUM(V.BountyAmount) as BountyAmount,
       SUM(CASE WHEN V.voteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedByOriginatorVotes,
       SUM(CASE WHEN V.voteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
       SUM(CASE WHEN V.voteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
   FROM
       Votes V
   JOIN
       Posts P ON V.PostId = P.Id
    JOIN
       ActiveUsers au ON p.OwnerUserId = au.UserId
   GROUP BY
       V.PostId, V.VoteTypeId, V.UserId, VoteDate, PostTitle, PostTypeId, P.OwnerUserId,PostScore
)
SELECT
    AU.UserId,
    AU.Reputation,
    AU.UserCreationDate,
    AU.LastAccessDate,
    AU.TotalPosts,
    AU.LastPostDate,
    AU.TotalQuestions,
    AU.TotalAnswers,
    AU.active_in_past_week,
    AU.posted_in_last_15_days,
    PP.PostId,
    PP.PostTypeId,
    PP.CreationDate,
    PP.Score,
    PP.ViewCount,
    PP.AnswerCount,
    PP.CommentCount,
    PP.OwnerUserId,
    PP.Title,
    PP.OwnerDisplayName,
    PP.OwnerReputation,
    PP.CommentId,
    PP.CommentScore,
    PP.CommentUserId,
    PP.CommentCreationDate,
    PP.CommentUserDisplayName,
    PP.CommentRank,
    VP.VoteTypeId,
    VP.VoterId,
    VP.VoteDate,
    VP.PostTitle,
    VP.VoteCount,
    VP.BountyAmount,
    VP.AcceptedByOriginatorVotes,
    VP.Upvotes,
    VP.Downvotes
FROM
    ActiveUsers AU
JOIN
    PopularPosts PP ON AU.UserId = PP.OwnerUserId
LEFT JOIN
    VotingPatterns VP ON PP.PostId = VP.PostId
ORDER BY
    AU.Reputation DESC,
    PP.Score DESC,
        VP.VoteCount DESC
LIMIT
    1000;
