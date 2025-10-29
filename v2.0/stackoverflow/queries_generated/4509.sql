-- {"query": "4509.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1339} 
WITH RankedAnswers AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER(PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as rn
    FROM Posts a
    WHERE a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL AND a.Score > -5
),
QuestionScores AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionOwnerUserId,
        q.Score AS QuestionScore,
        q.CreationDate AS QuestionCreationDate,
        q.AnswerCount,
        q.FavoriteCount,
        q.ViewCount,
        q.Title,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = q.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount
    FROM Posts q
    WHERE q.PostTypeId = 1 AND q.OwnerUserId IS NOT NULL AND q.CreationDate > '2010-01-01'
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(DISTINCT ph.PostId) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (2, 5)) AS EditedPostCount,
        (SELECT COUNT(DISTINCT w.PostId) FROM Votes w WHERE w.UserId = u.Id AND w.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(DISTINCT b.Id) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgeCount
    FROM Users u
    WHERE u.Id > 0 AND u.Reputation > 100
)
SELECT
    qs.QuestionId,
    qs.Title,
    qs.QuestionScore,
    qs.QuestionCreationDate,
    qs.AnswerCount,
    qs.FavoriteCount,
    qs.ViewCount,
    qs.DuplicateLinkCount,
    COALESCE(ua_q.DisplayName, 'Community') AS QuestionOwnerDisplayName,
    ua_q.Reputation AS QuestionOwnerReputation,
    ua_q.UserCreationDate AS QuestionOwnerCreationDate,
    COALESCE(ra.AnswerId, -1) AS TopAnswerId,
    ra.Score AS TopAnswerScore,
    ra.AnswerCreationDate AS TopAnswerCreationDate,
    COALESCE(ua_a.DisplayName, 'Anonymous') AS TopAnswerOwnerDisplayName,
    ua_a.Reputation AS TopAnswerOwnerReputation,
    ua_a.GoldBadgeCount AS TopAnswerOwnerGoldBadges,
    CASE
        WHEN qs.ViewCount > 10000 AND qs.AnswerCount > 5 AND qs.QuestionScore > 50 THEN 'Popular & Highly Rated'
        WHEN qs.ViewCount > 5000 AND qs.AnswerCount > 3 AND qs.QuestionScore > 20 THEN 'Moderately Popular'
        WHEN qs.DuplicateLinkCount > 0 THEN 'Potential Duplicate'
        WHEN qs.FavoriteCount > 10 THEN 'Frequently Favorited'
        ELSE 'Standard'
    END AS QuestionCategory,
    LENGTH(qs.Title) AS TitleLength,
    UPPER(SUBSTRING(qs.Title FROM 1 FOR 3)) AS TitlePrefix,
    CASE
        WHEN ua_q.UserCreationDate < qs.QuestionCreationDate - INTERVAL '1 year' THEN 'Old User'
        ELSE 'New User'
    END AS UserAgeCategory,
    CASE
        WHEN ra.Score IS NULL THEN 0
        WHEN ra.Score = 0 THEN 0
        ELSE (qs.QuestionScore - ra.Score) * 1.0 / NULLIF(qs.QuestionScore, 0)
    END AS ScoreDifferenceRatio
FROM QuestionScores qs
LEFT OUTER JOIN RankedAnswers ra ON qs.QuestionId = ra.QuestionId AND ra.rn = 1
LEFT OUTER JOIN UserActivity ua_q ON qs.QuestionOwnerUserId = ua_q.UserId
LEFT OUTER JOIN UserActivity ua_a ON ra.OwnerUserId = ua_a.UserId
WHERE qs.QuestionScore > 0
UNION ALL
SELECT
    NULL AS QuestionId,
    NULL AS Title,
    NULL AS QuestionScore,
    NULL AS QuestionCreationDate,
    NULL AS AnswerCount,
    NULL AS FavoriteCount,
    NULL AS ViewCount,
    NULL AS DuplicateLinkCount,
    NULL AS QuestionOwnerDisplayName,
    NULL AS QuestionOwnerReputation,
    NULL AS QuestionOwnerCreationDate,
    NULL AS TopAnswerId,
    NULL AS TopAnswerScore,
    NULL AS TopAnswerCreationDate,
    NULL AS TopAnswerOwnerDisplayName,
    NULL AS TopAnswerOwnerReputation,
    NULL AS TopAnswerOwnerGoldBadges,
    'Aggregate' AS QuestionCategory,
    AVG(CAST(LENGTH(qs.Title) AS NUMERIC)) AS TitleLength,
    NULL AS TitlePrefix,
    NULL AS UserAgeCategory,
    AVG(CASE WHEN ra.Score IS NULL THEN 0 WHEN ra.Score = 0 THEN 0 ELSE (qs.QuestionScore - ra.Score) * 1.0 / NULLIF(qs.QuestionScore, 0) END) AS ScoreDifferenceRatio
FROM QuestionScores qs
LEFT OUTER JOIN RankedAnswers ra ON qs.QuestionId = ra.QuestionId AND ra.rn = 1
WHERE qs.QuestionScore > 0;