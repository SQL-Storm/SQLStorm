-- {"query": "2925.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1467} 
WITH RecentTopQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName AS OwnerName,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
      AND p.Score IS NOT NULL
), UserBadgeCounts AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
), UserStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(bc.GoldBadges,0) AS GoldBadges,
        COALESCE(bc.SilverBadges,0) AS SilverBadges,
        COALESCE(bc.BronzeBadges,0) AS BronzeBadges,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        -- Calculate badge score as weighted sum
        (COALESCE(bc.GoldBadges,0) * 5 + COALESCE(bc.SilverBadges,0) * 3 + COALESCE(bc.BronzeBadges,0)) AS BadgeScore
    FROM Users u
    LEFT JOIN UserBadgeCounts bc ON u.Id = bc.UserId
), QuestionAnswers AS (
    SELECT
        q.Id AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.CreationDate) AS LastAnswerDate
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
), QuestionCloseInfo AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastCloseDate,
        STRING_AGG(DISTINCT crt.Name, ', ') AS CloseReasons
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON CAST(ph.Comment AS int) = crt.Id
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
), QuestionWithLinkCounts AS (
    SELECT
        q.Id,
        COUNT(DISTINCT pl.Id) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedCount,
        COUNT(DISTINCT pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateCount
    FROM Posts q
    LEFT JOIN PostLinks pl ON pl.PostId = q.Id
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
), TagInfo AS (
    SELECT
        t.TagName,
        t.Count,
        COALESCE(pq.Score,0) AS TagMaxQuestionScore,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY pq.Score DESC NULLS LAST) AS rn
    FROM Tags t
    LEFT JOIN Posts pq ON t.ExcerptPostId = pq.Id AND pq.PostTypeId = 1
    WHERE t.TagName IS NOT NULL
), FinalCTE AS (
    SELECT
        rtq.Id AS QuestionId,
        rtq.Title,
        rtq.OwnerUserId,
        rtq.OwnerName,
        rtq.CreationDate AS QuestionCreation,
        rtq.Score AS QuestionScore,
        rtq.ViewCount,
        rtq.Tags,
        us.Reputation,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.BadgeScore,
        qa.AnswerCount,
        ROUND(qa.AvgAnswerScore::numeric,2) AS AvgAnswerScore,
        qa.LastAnswerDate,
        qci.LastCloseDate,
        qci.CloseReasons,
        qwl.LinkedCount,
        qwl.DuplicateCount,
        -- Extract first tag for demonstration and parse tags string array
        split_part(rtq.Tags, '><', 1) AS FirstTag,
        -- Subquery to count answers with score above question score (correlated subquery)
        (SELECT COUNT(*) FROM Posts a_sub
         WHERE a_sub.ParentId = rtq.Id
           AND a_sub.Score > rtq.Score) AS HighScoreAnswers,
        -- Window function for ranking questions by score descending over all recent questions
        RANK() OVER (ORDER BY rtq.Score DESC) AS ScoreRank
    FROM RecentTopQuestions rtq
    LEFT JOIN UserStats us ON rtq.OwnerUserId = us.UserId
    LEFT JOIN QuestionAnswers qa ON rtq.Id = qa.QuestionId
    LEFT JOIN QuestionCloseInfo qci ON rtq.Id = qci.PostId
    LEFT JOIN QuestionWithLinkCounts qwl ON rtq.Id = qwl.Id
)
SELECT
    f.QuestionId,
    LEFT(f.Title, 80) || CASE WHEN LENGTH(f.Title) > 80 THEN '...' ELSE '' END AS TitleSnippet,
    f.OwnerUserId,
    f.OwnerName,
    TO_CHAR(f.QuestionCreation, 'YYYY-MM-DD') AS QuestionCreationDate,
    f.QuestionScore,
    f.ViewCount,
    f.Tags,
    f.Reputation AS OwnerReputation,
    f.GoldBadges,
    f.SilverBadges,
    f.BronzeBadges,
    f.BadgeScore,
    f.AnswerCount,
    f.AvgAnswerScore,
    TO_CHAR(f.LastAnswerDate, 'YYYY-MM-DD') AS LastAnswerDate,
    TO_CHAR(f.LastCloseDate, 'YYYY-MM-DD') AS LastCloseDate,
    COALESCE(f.CloseReasons, 'None') AS CloseReasons,
    f.LinkedCount,
    f.DuplicateCount,
    f.HighScoreAnswers,
    f.ScoreRank,
    -- Complex string expression showing concatenated and formatted badge information
    CONCAT(
        'Badges(Gold: ', f.GoldBadges, ', Silver: ', f.SilverBadges,
        ', Bronze: ', f.BronzeBadges, ')'
    ) AS BadgeSummary,
    -- NULL logic example: if user location present, else default string
    COALESCE(
        NULLIF(TRIM(us.Location), ''),
        'Location Unknown'
    ) AS UserLocation
FROM FinalCTE f
LEFT JOIN Users us ON f.OwnerUserId = us.Id
WHERE f.rn = 1
  AND f.QuestionScore > 5
ORDER BY f.ScoreRank, f.QuestionCreation DESC
LIMIT 50;