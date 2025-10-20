WITH RankedAnswers AS (
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.Score,
        p.CreationDate,
        u.Id AS UserId,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS RankByScore
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 2
      AND p.Score > 0
),
TopAnswersWithBadges AS (
    SELECT
        ra.AnswerId,
        ra.QuestionId,
        ra.Score,
        ra.CreationDate,
        ra.UserId,
        ra.Reputation,
        ra.RankByScore,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM RankedAnswers ra
    LEFT JOIN Badges b ON ra.UserId = b.UserId AND b.Date < ra.CreationDate
    WHERE ra.RankByScore <= 3
    GROUP BY ra.AnswerId, ra.QuestionId, ra.Score, ra.CreationDate, ra.UserId, ra.Reputation, ra.RankByScore
),
QuestionStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        u.Id AS OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        COUNT(c.Id) AS CommentCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS VoteScoreTotal,
        STRING_AGG(DISTINCT t.TagName, ', ') AS TagList,
        (CASE WHEN q.Tags IS NULL OR q.Tags = '' THEN 0 ELSE array_length(string_to_array(substring(q.Tags,2,length(q.Tags)-2), '><'),1) END) AS TagCount
    FROM Posts q
    JOIN Users u ON q.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.PostId = q.Id
    LEFT JOIN Votes v ON v.PostId = q.Id
    LEFT JOIN Tags t ON POSITION('<' || t.TagName || '>' IN q.Tags) > 0
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags, u.Id, u.DisplayName, u.Reputation
),
AnswerLinkStats AS (
    SELECT
        pa.Id AS AnswerId,
        COUNT(CASE WHEN pl.LinkTypeId = 1 THEN 1 END) AS LinkedCount,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN 1 END) AS DuplicateCount,
        MAX(pl.CreationDate) AS LastLinkDate
    FROM Posts pa
    LEFT JOIN PostLinks pl ON pa.Id = pl.PostId
    WHERE pa.PostTypeId = 2
    GROUP BY pa.Id
)
SELECT
    qs.QuestionId,
    qs.Title,
    qs.CreationDate AS QuestionCreated,
    qs.QuestionScore,
    qs.ViewCount,
    qs.OwnerDisplayName,
    qs.OwnerReputation,
    qs.CommentCount,
    COALESCE(qs.VoteScoreTotal, 0) AS VoteScoreTotal,
    qs.TagCount,
    qs.TagList,
    ta.AnswerId,
    ta.Score AS AnswerScore,
    ta.CreationDate AS AnswerCreated,
    ta.UserId AS AnswererUserId,
    ta.Reputation AS AnswererReputation,
    ta.GoldBadges,
    ta.SilverBadges,
    ta.BronzeBadges,
    als.LinkedCount,
    als.DuplicateCount,
    als.LastLinkDate
FROM QuestionStats qs
JOIN TopAnswersWithBadges ta ON qs.QuestionId = ta.QuestionId
LEFT JOIN AnswerLinkStats als ON ta.AnswerId = als.AnswerId
WHERE qs.ViewCount > 1000
  AND qs.QuestionScore > 5
  AND ta.Reputation > 1000
  AND (ta.GoldBadges + ta.SilverBadges + ta.BronzeBadges) >= 3
ORDER BY qs.ViewCount DESC, ta.Score DESC, ta.GoldBadges DESC
LIMIT 50;