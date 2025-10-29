-- {"query": "4397.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1700} 

WITH RankedAnswers AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS rn
    FROM Posts a
    WHERE a.PostTypeId = 2
),
QuestionStats AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionOwnerUserId,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.AnswerCount,
        q.FavoriteCount,
        q.ViewCount,
        q.Title,
        q.Tags,
        (
            SELECT COUNT(*)
            FROM Comments c
            WHERE c.PostId = q.Id
        ) AS CommentCountForQuestion,
        CASE WHEN q.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        (
            SELECT COUNT(ph.Id)
            FROM PostHistory ph
            WHERE ph.PostId = q.Id
            AND ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35, 36)
        ) AS ModerationEventCount
    FROM Posts q
    WHERE q.PostTypeId = 1
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        (
            SELECT COUNT(*)
            FROM Badges b
            WHERE b.UserId = u.Id
            AND b.Class = 1
        ) AS GoldBadgeCount,
        (
            SELECT COUNT(*)
            FROM Badges b
            WHERE b.UserId = u.Id
            AND b.Class = 2
        ) AS SilverBadgeCount,
        (
            SELECT COUNT(*)
            FROM Badges b
            WHERE b.UserId = u.Id
            AND b.Class = 3
        ) AS BronzeBadgeCount,
        (
            SELECT COUNT(ph.Id)
            FROM PostHistory ph
            WHERE ph.UserId = u.Id
            AND ph.PostHistoryTypeId = 24 -- Suggested Edit Applied
        ) AS SuggestedEditsApplied
    FROM Users u
)
SELECT
    qs.QuestionId,
    qs.Title AS QuestionTitle,
    qs.Tags AS QuestionTags,
    qs.QuestionCreationDate,
    qs.QuestionScore,
    qs.AnswerCount AS QuestionAnswerCount,
    qs.FavoriteCount AS QuestionFavoriteCount,
    qs.ViewCount AS QuestionViewCount,
    qs.CommentCountForQuestion,
    qs.IsClosed,
    qs.ModerationEventCount,
    ra.AnswerId AS BestAnswerId,
    ra.AnswerScore AS BestAnswerScore,
    ra.AnswerCreationDate AS BestAnswerCreationDate,
    ua_q.DisplayName AS QuestionOwnerDisplayName,
    ua_q.Reputation AS QuestionOwnerReputation,
    ua_q.GoldBadgeCount AS QuestionOwnerGoldBadges,
    ua_q.SilverBadgeCount AS QuestionOwnerSilverBadges,
    ua_q.BronzeBadgeCount AS QuestionOwnerBronzeBadges,
    ua_a.DisplayName AS BestAnswerOwnerDisplayName,
    ua_a.Reputation AS BestAnswerOwnerReputation,
    ua_a.SuggestedEditsApplied AS BestAnswerOwnerEditsApplied,
    CASE
        WHEN qs.QuestionScore > 1000 AND qs.FavoriteCount > 50 THEN 'High Impact'
        WHEN qs.AnswerCount > 20 AND qs.QuestionScore > 100 THEN 'Highly Discussed'
        WHEN qs.IsClosed = 1 AND qs.ModerationEventCount > 5 THEN 'Frequently Moderated'
        WHEN qs.QuestionOwnerReputation < 1000 THEN 'Newer Contributor'
        ELSE 'Standard'
    END AS QuestionCategory,
    DATEDIFF(day, qs.QuestionCreationDate, GETDATE()) AS QuestionAgeInDays,
    UPPER(SUBSTRING(qs.Title, 1, 3)) AS TitlePrefix,
    (ua_q.Reputation + COALESCE(ua_a.Reputation, 0)) AS TotalOwnerReputation,
    CASE WHEN qs.Tags LIKE '%<sql>%' THEN 1 ELSE 0 END AS HasSqlTag
FROM QuestionStats qs
LEFT JOIN RankedAnswers ra ON qs.QuestionId = ra.QuestionId AND ra.rn = 1
LEFT JOIN UserActivity ua_q ON qs.QuestionOwnerUserId = ua_q.UserId
LEFT JOIN UserActivity ua_a ON ra.OwnerUserId = ua_a.UserId
WHERE qs.QuestionCreationDate BETWEEN '2020-01-01' AND '2023-01-01'
  AND qs.Title IS NOT NULL
  AND qs.AnswerCount > 0
  AND qs.OwnerUserId <> -1 -- Exclude community-owned questions that might not have a valid owner
UNION
SELECT
    qs.QuestionId,
    qs.Title AS QuestionTitle,
    qs.Tags AS QuestionTags,
    qs.QuestionCreationDate,
    qs.QuestionScore,
    qs.AnswerCount AS QuestionAnswerCount,
    qs.FavoriteCount AS QuestionFavoriteCount,
    qs.ViewCount AS QuestionViewCount,
    qs.CommentCountForQuestion,
    qs.IsClosed,
    qs.ModerationEventCount,
    NULL AS BestAnswerId,
    NULL AS BestAnswerScore,
    NULL AS BestAnswerCreationDate,
    ua_q.DisplayName AS QuestionOwnerDisplayName,
    ua_q.Reputation AS QuestionOwnerReputation,
    ua_q.GoldBadgeCount AS QuestionOwnerGoldBadges,
    ua_q.SilverBadgeCount AS QuestionOwnerSilverBadges,
    ua_q.BronzeBadgeCount AS QuestionOwnerBronzeBadges,
    NULL AS BestAnswerOwnerDisplayName,
    NULL AS BestAnswerOwnerReputation,
    NULL AS BestAnswerOwnerEditsApplied,
    CASE
        WHEN qs.QuestionScore > 1000 AND qs.FavoriteCount > 50 THEN 'High Impact'
        WHEN qs.AnswerCount > 20 AND qs.QuestionScore > 100 THEN 'Highly Discussed'
        WHEN qs.IsClosed = 1 AND qs.ModerationEventCount > 5 THEN 'Frequently Moderated'
        WHEN qs.OwnerUserId <> -1 AND qs.QuestionOwnerReputation < 1000 THEN 'Newer Contributor'
        ELSE 'Standard'
    END AS QuestionCategory,
    DATEDIFF(day, qs.QuestionCreationDate, GETDATE()) AS QuestionAgeInDays,
    UPPER(SUBSTRING(qs.Title, 1, 3)) AS TitlePrefix,
    ua_q.Reputation AS TotalOwnerReputation,
    CASE WHEN qs.Tags LIKE '%<sql>%' THEN 1 ELSE 0 END AS HasSqlTag
FROM QuestionStats qs
LEFT JOIN UserActivity ua_q ON qs.OwnerUserId = ua_q.UserId
WHERE qs.QuestionCreationDate BETWEEN '2020-01-01' AND '2023-01-01'
  AND qs.AnswerCount = 0
  AND qs.OwnerUserId <> -1;
