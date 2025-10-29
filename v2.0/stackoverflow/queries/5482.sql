-- {"query": "5482.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1037}
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.LastEditDate,
    p.Body,
    p.ParentId,
    p.AcceptedAnswerId,
    p.LastEditorUserId,
    p.LastEditorDisplayName,
    p.FavoriteCount,
    p.ContentLicense,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC NULLS LAST,
        p.ViewCount DESC NULLS LAST,
        p.CreationDate DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  LEFT JOIN PostLinks pl2 ON pl.RelatedPostId = pl2.PostId
),
MostActiveQuestions AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.CreationDate,
    rp.OwnerUserId,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.CommentCount,
    rp.AnswerCount,
    rp.LastActivityDate,
    rp.Body,
    rp.AcceptedAnswerId,
    rp.LastEditorUserId,
    rp.LastEditorDisplayName,
    rp.FavoriteCount,
    rp.ContentLicense
  FROM RankedPosts rp
  WHERE rp.PostTypeId = 1 -- Questions
    AND rp.rn <= 100
),
TagUsage AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    t.IsModeratorOnly
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
TopTagWikis AS (
  SELECT
    tu.TagName,
    tu.Count,
    tu.ExcerptPostId,
    tu.WikiPostId
  FROM (
      SELECT
        TagName,
        Count,
        ExcerptPostId,
        WikiPostId,
        ROW_NUMBER() OVER (ORDER BY Count DESC, TagName ASC) AS rn
      FROM TagUsage
  ) tu
  WHERE tu.rn <= 5
),
RecentVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount,
    U.DisplayName
  FROM Votes v
  LEFT JOIN Users U ON v.UserId = U.Id
  WHERE v.VoteTypeId IN (2,3,16) -- UpMod, DownMod, ModeratorReview (representative)
),
Coalesced AS (
  SELECT
    mq.Id,
    mq.Title,
    mq.CreationDate,
    mq.OwnerUserId,
    mq.Score,
    mq.ViewCount,
    mq.Tags,
    mq.CommentCount,
    mq.AnswerCount,
    mq.LastActivityDate,
    mq.Body,
    mq.AcceptedAnswerId,
    mq.LastEditorUserId,
    mq.LastEditorDisplayName,
    mq.FavoriteCount,
    mq.ContentLicense,
    array_agg(DISTINCT t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS TopTags,
    array_agg(DISTINCT rv.VoteTypeId) FILTER (WHERE rv.VoteTypeId IS NOT NULL) AS RecentVoteTypes
  FROM MostActiveQuestions mq
  LEFT JOIN Tags t ON t.ExcerptPostId = mq.Id OR t.WikiPostId = mq.Id
  LEFT JOIN RecentVotes rv ON rv.PostId = mq.Id
  GROUP BY mq.Id, mq.Title, mq.CreationDate, mq.OwnerUserId, mq.Score, mq.ViewCount,
           mq.Tags, mq.CommentCount, mq.AnswerCount, mq.LastActivityDate, mq.Body,
           mq.AcceptedAnswerId, mq.LastEditorUserId, mq.LastEditorDisplayName,
           mq.FavoriteCount, mq.ContentLicense
)
SELECT
  COALESCED.Id,
  COALESCED.Title,
  COALESCED.CreationDate,
  COALESCED.OwnerUserId,
  COALESCED.Score,
  COALESCED.ViewCount,
  COALESCED.Tags,
  COALESCED.CommentCount,
  COALESCED.AnswerCount,
  COALESCED.LastActivityDate,
  COALESCED.Body,
  COALESCED.AcceptedAnswerId,
  COALESCED.LastEditorUserId,
  COALESCED.LastEditorDisplayName,
  COALESCED.FavoriteCount,
  COALESCED.ContentLicense,
  COALESCED.TopTags,
  COALESCED.RecentVoteTypes
FROM Coalesced COALESCED
ORDER BY
  COALESCED.Score DESC NULLS LAST,
  COALESCED.ViewCount DESC NULLS LAST,
  COALESCED.CreationDate DESC
FETCH FIRST 100 ROWS ONLY;