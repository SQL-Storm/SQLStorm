WITH QuestionTags AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId AS QuestionOwnerUserId,
        UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)), '><')) AS TagName,
        p.CreationDate AS QuestionCreated
    FROM Posts p
    WHERE p.PostTypeId = 1
),
Answers AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        a.CommentCount,
        a.FavoriteCount
    FROM Posts a
    WHERE a.PostTypeId = 2
),
UserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) AS FavoriteCount
    FROM Users u
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagBadges AS (
    SELECT
        b.UserId,
        t.TagName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    JOIN Tags t ON b.TagBased = TRUE AND b.Name = t.TagName
    GROUP BY b.UserId, t.TagName
),
AnswerAggregates AS (
    SELECT
        qt.TagName,
        a.OwnerUserId,
        COUNT(*) AS AnswerCount,
        AVG(a.Score) AS AvgScore,
        MIN(a.CreationDate) AS FirstAnswerDate,
        MAX(a.CreationDate) AS LastAnswerDate,
        ROW_NUMBER() OVER (PARTITION BY qt.TagName ORDER BY AVG(a.Score) DESC) AS RankByScore
    FROM QuestionTags qt
    JOIN Answers a ON a.QuestionId = qt.QuestionId
    GROUP BY qt.TagName, a.OwnerUserId
)

SELECT
    aa.TagName,
    u.DisplayName,
    u.Reputation,
    aa.AnswerCount,
    ROUND(CAST(aa.AvgScore AS NUMERIC), 2) AS AvgScore,
    aa.FirstAnswerDate,
    aa.LastAnswerDate,
    us.UpVoteCount,
    us.DownVoteCount,
    us.FavoriteCount,
    COALESCE(tb.GoldBadges, 0)   AS GoldBadges,
    COALESCE(tb.SilverBadges, 0) AS SilverBadges,
    COALESCE(tb.BronzeBadges, 0) AS BronzeBadges,
    CASE
        WHEN us.UpVoteCount > us.DownVoteCount THEN 'Positive'
        WHEN us.UpVoteCount < us.DownVoteCount THEN 'Negative'
        ELSE 'Neutral'
    END AS VoteSentiment,
    CONCAT(aa.TagName, ' - ', COALESCE(u.DisplayName, '[deleted]')) AS TagUserLabel,
    aa.RankByScore
FROM AnswerAggregates aa
LEFT JOIN Users u       ON u.Id = aa.OwnerUserId
LEFT JOIN UserStats us  ON us.UserId = aa.OwnerUserId
LEFT JOIN TagBadges tb  ON tb.UserId = aa.OwnerUserId AND tb.TagName = aa.TagName
WHERE aa.RankByScore <= 5

UNION ALL

SELECT
    t.TagName,
    NULL AS DisplayName,
    NULL AS Reputation,
    0 AS AnswerCount,
    NULL AS AvgScore,
    NULL AS FirstAnswerDate,
    NULL AS LastAnswerDate,
    0 AS UpVoteCount,
    0 AS DownVoteCount,
    0 AS FavoriteCount,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    'NoAnswers' AS VoteSentiment,
    t.TagName || ' - No answers' AS TagUserLabel,
    CAST(NULL AS INTEGER) AS RankByScore
FROM Tags t
WHERE NOT EXISTS (
    SELECT 1
    FROM QuestionTags qt
    WHERE qt.TagName = t.TagName
)

ORDER BY TagName, RankByScore NULLS LAST, VoteSentiment;