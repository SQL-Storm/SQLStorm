-- {"query": "22028.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1139} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Location,
        u.Reputation,
        COALESCE(u.Views, 0) AS Views,
        COALESCE(u.AboutMe, '') AS AboutMe,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT SUM(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS TotalScore,
        (SELECT AVG(LENGTH(p.Body)) FROM Posts p WHERE p.OwnerUserId = u.Id) AS AvgPostLength
    FROM Users u
),
TopTags AS (
    SELECT 
        p.OwnerUserId,
        UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS Tag,
        COUNT(*) AS TagCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))
),
FavoriteTag AS (
    SELECT 
        OwnerUserId,
        Tag,
        ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY TagCount DESC) AS Rn
    FROM TopTags
),
PostHistorySummary AS (
    SELECT 
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) AS EditCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseCount,
        STRING_AGG(DISTINCT CASE WHEN ph.PostHistoryTypeId = 24 THEN ph.UserDisplayName END, ', ') AS EditorNames
    FROM PostHistory ph
    GROUP BY ph.PostId
),
VoteSummary AS (
    SELECT 
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptsGiven
    FROM Votes v
    GROUP BY v.UserId
),
CompositeScore AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Location,
        us.Reputation,
        us.Views,
        LENGTH(us.AboutMe) AS AboutMeLength,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.QuestionCount,
        us.AnswerCount,
        us.TotalScore,
        us.AvgPostLength,
        ft.Tag AS FavoriteTag,
        COALESCE(vs.UpvotesGiven, 0) AS UpvotesGiven,
        COALESCE(vs.DownvotesGiven, 0) AS DownvotesGiven,
        COALESCE(vs.AcceptsGiven, 0) AS AcceptsGiven,
        ROW_NUMBER() OVER (PARTITION BY us.Location ORDER BY (us.Reputation * 1.0 + COALESCE(us.TotalScore, 0) + us.GoldBadges * 100 + us.SilverBadges * 10 + us.BronzeBadges) / NULLIF(us.Views + 1, 0) DESC) AS RankByLocation,
        CASE 
            WHEN us.AboutMe IS NULL OR TRIM(us.AboutMe) = '' THEN 'No Bio'
            ELSE LEFT(us.AboutMe, 50) || '...'
        END AS BioSnippet
    FROM UserStats us
    LEFT JOIN FavoriteTag ft ON us.UserId = ft.OwnerUserId AND ft.Rn = 1
    LEFT OUTER JOIN VoteSummary vs ON us.UserId = vs.UserId
)
SELECT 
    cs.UserId,
    cs.DisplayName,
    cs.Location,
    cs.Reputation,
    cs.Views,
    cs.AboutMeLength,
    cs.GoldBadges,
    cs.SilverBadges,
    cs.BronzeBadges,
    cs.QuestionCount,
    cs.AnswerCount,
    cs.TotalScore,
    cs.AvgPostLength,
    cs.FavoriteTag,
    cs.UpvotesGiven,
    cs.DownvotesGiven,
    cs.AcceptsGiven,
    cs.RankByLocation,
    cs.BioSnippet,
    (
        SELECT AVG(phs.EditCount) 
        FROM PostHistorySummary phs 
        WHERE phs.PostId IN (SELECT Id FROM Posts p WHERE p.OwnerUserId = cs.UserId)
    ) AS AvgEditsPerPost
FROM CompositeScore cs
WHERE cs.RankByLocation <= 10
    AND cs.Reputation > 100
    AND (cs.QuestionCount + cs.AnswerCount) > 5
ORDER BY cs.Location, cs.RankByLocation;