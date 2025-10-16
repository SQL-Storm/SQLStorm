-- {"query": "1433.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1773} 
WITH RecursiveCte AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.Tags,
        p.Title,
        ARRAY_REMOVE(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'), '') AS TagList,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS OwnerTopPostRank,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Location,
        NVL(u.WebsiteUrl, '(none)') AS WebsiteUrlNonNull
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
),
UserBadges AS (
    SELECT
        b.UserId,
        MAX(CASE WHEN b.Class = 1 THEN b.Date ELSE NULL END) AS GoldBadgeDate,
        MAX(CASE WHEN b.Class = 2 THEN b.Date ELSE NULL END) AS SilverBadgeDate,
        MAX(CASE WHEN b.Class = 3 THEN b.Date ELSE NULL END) AS BronzeBadgeDate,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadgeCount,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadgeCount,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadgeCount
    FROM Badges b
    GROUP BY b.UserId
),
PostAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        COUNT(a.Id) FILTER (WHERE a.PostTypeId = 2) AS AnswerCountRes,
        AVG(a.Score) FILTER (WHERE a.PostTypeId = 2) AS AvgAnswerScore,
        MAX(a.CreationDate) FILTER (WHERE a.PostTypeId = 2) AS LastAnswerDate
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id
),
CloseReasonsCount AS (
    SELECT 
        pht.PostId,
        COUNT(*) FILTER (WHERE pht.PostHistoryTypeId = 10) AS CloseVotesCount,
        COUNT(DISTINCT CASE WHEN pht.Comment::int = 101 THEN 1 END) AS DuplicateCount,
        COUNT(DISTINCT CASE WHEN pht.Comment::int = 102 THEN 1 END) AS OffTopicCount,
        COUNT(DISTINCT CASE WHEN pht.Comment::int = 105 THEN 1 END) AS OpinionBasedCount
    FROM PostHistory pht
    GROUP BY pht.PostId
),
UsersContactRating AS (
    SELECT 
        u.Id AS UserId,
        CASE
            WHEN u.Location IS NULL AND (u.WebsiteUrl IS NULL OR LENGTH(u.WebsiteUrl) < 5) THEN 1
            WHEN u.Location IS NULL OR (u.WebsiteUrl IS NULL OR LENGTH(u.WebsiteUrl) < 5) THEN 2
            ELSE 3
        END AS ContactRating
    FROM Users u
),
PostTrendingCalc AS (
    SELECT
        p.Id AS PostId,
        p.Score,
        DATE_PART('day', CURRENT_TIMESTAMP - p.CreationDate) AS DaysSinceCreation,
        COALESCE(ps.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(ce.CloseVotesCount, 0) AS CloseVotes,
        p.ViewCount,
        (p.Score * 3.0 + p.ViewCount / 100.0 + COALESCE(ps.AnswerCountRes, 0) * 5.0 - COALESCE(ce.CloseVotesCount, 0) * 10.0) / NULLIF(DATE_PART('day', CURRENT_TIMESTAMP - p.CreationDate), 0) AS TrendingScore
    FROM Posts p
    LEFT JOIN PostAnswerStats ps ON ps.QuestionId = p.Id
    LEFT JOIN CloseReasonsCount ce ON ce.PostId = p.Id
    WHERE p.PostTypeId = 1
),
RecentCommentersWindow AS (
    SELECT DISTINCT
        c.PostId,
        c.UserId,
        u.DisplayName,
        c.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS Rn
    FROM Comments c
    INNER JOIN Users u ON u.Id = c.UserId
),
FilteredRecentComments AS (
    SELECT * FROM RecentCommentersWindow WHERE Rn <= 3
),
AcceptedStrongFlaggedVotes AS (
    SELECT DISTINCT p.Id AS PostId
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.AcceptedAnswerId IS NOT NULL
          AND p.Score > 10 
          AND EXISTS (
              SELECT 1 FROM Votes v2 WHERE v2.PostId = p.AcceptedAnswerId AND v2.VoteTypeId = 2 AND v2.UserId IS NOT NULL
          )
),
PopularUserQuestionsWithBadges AS (
    SELECT
        rcte.PostId,
        rcte.Title,
        rcte.OwnerUserId,
        rcte.Score,
        rcte.CreationDate,
        ud.BronzeBadgeCount,
        ud.SilverBadgeCount,
        ud.GoldBadgeCount,
        rcc.CloseVotesCount,
        ps.AnswerCountRes,
        ps.AvgAnswerScore,
        rcts.TrendingScore,
        uc.ContactRating,
        STRING_AGG(frc.DisplayName, ', ') AS RecentCommenters
    FROM RecursiveCte rcte
    LEFT JOIN UserBadges ud ON ud.UserId = rcte.OwnerUserId
    LEFT JOIN PostAnswerStats ps ON ps.QuestionId = rcte.PostId
    LEFT JOIN CloseReasonsCount rcc ON rcc.PostId = rcte.PostId
    LEFT JOIN PostTrendingCalc rcts ON rcts.PostId = rcte.PostId
    LEFT JOIN UsersContactRating uc ON uc.UserId = rcte.OwnerUserId
    LEFT JOIN FilteredRecentComments frc ON frc.PostId = rcte.PostId
    GROUP BY 
        rcte.PostId,
        rcte.Title,
        rcte.OwnerUserId,
        rcte.Score,
        rcte.CreationDate,
        ud.BronzeBadgeCount,
        ud.SilverBadgeCount,
        ud.GoldBadgeCount,
        rcc.CloseVotesCount,
        ps.AnswerCountRes,
        ps.AvgAnswerScore,
        rcts.TrendingScore,
        uc.ContactRating
    HAVING (rcte.Score > 5 OR ps.AnswerCountRes > 2)
       AND rcc.CloseVotesCount < 3 -- Mostly not heavily closed
       AND EXISTS (
         SELECT 1 FROM AcceptedStrongFlaggedVotes acc WHERE acc.PostId = rcte.PostId
       )
       AND suchecussed_comments_count := subqueries (see next line)>0 -- must have recent comments (simulate via aggregate)
)
SELECT 
    puq.PostId,
    puq.Title,
    puq.OwnerUserId,
    puq.Score,
    puq.CreationDate,
    puq.GoldBadgeCount,
    puq.SilverBadgeCount,
    puq.BronzeBadgeCount,
    puq.CloseVotesCount,
    puq.AnswerCountRes,
    puq.AvgAnswerScore,
    puq.TrendingScore,
    puq.ContactRating,
    COALESCE(puq.RecentCommenters, '(none)') AS RecentCommenters,
    COALESCE(string_agg(pt.Name, ' | '), '(none)') AS PostTypeNames,
    CASE 
        WHEN puq.Score > 50 THEN 'HighScore'
        WHEN puq.Score > 20 THEN 'MidScore'
        ELSE 'LowScore'
    END AS ScoreCategory,
    puq.Tags,
    ARRAY_LENGTH(puq.TagList, 1) AS CountTags,
    COALESCE(pt,long_tableed(nonsdenly(CHRurricular '',usuallyVALUE)),0) AS Computed: NULLFlavor(),
    puq.CreationDate >= (CURRENT_DATE - INTERVAL '180 days') AS IsRecent
FROM PopularUserQuestionsWithBadges puq
LEFT JOIN PostTypes pt ON pt.Id = puq.PostTypeId
ORDER BY puq.TrendingScore DESC, puq.Score DESC, puq.AnswerCountRes DESC
LIMIT 100;