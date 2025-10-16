-- {"query": "1237.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1762} 

WITH UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT p.Id) AS TotalQuestions,
        COUNT(DISTINCT a.Id) AS TotalAnswers,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(a.Score) FILTER (WHERE a.PostTypeId = 2) AS AvgAnswerScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST, GoldBadges DESC) AS UserRank
    FROM
        Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
        LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    WHERE u.Reputation > 10
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
FilteredPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags
    FROM Posts p
    WHERE p.CreationDate > now() - interval '2 years' AND p.Score >= 1
),
LinkedDuplicates AS (
    SELECT DISTINCT
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
),
PostAcceptedAnswerScores AS (
    SELECT
        q.Id AS QuestionId,
        a.Id AS AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    WHERE q.PostTypeId = 1 AND q.AcceptedAnswerId IS NOT NULL
),
PostCloseInfo AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment::int ELSE NULL END) AS CloseReasonId,
        MAX(ph.CreationDate) AS LastCloseDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
UserActivityWindow AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsInWindow,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersInWindow,
        COUNT(DISTINCT c.Id) AS CommentCount,
        ROUND(AVG(COALESCE(p.Score,0)), 2) AS AvgPostScore,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= now() - interval '6 months'
    LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate >= now() - interval '6 months'
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.CreationDate >= now() - interval '6 months'
    GROUP BY u.Id, u.DisplayName
),
TopTagsPerUser AS (
    SELECT
        p.OwnerUserId AS UserId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) AS Tag,
        COUNT(*) AS TagCount
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.Tags <> ''
    GROUP BY p.OwnerUserId, Tag
),
UserTopTagRanks AS (
    SELECT
        UserId,
        Tag,
        TagCount,
        RANK() OVER (PARTITION BY UserId ORDER BY TagCount DESC) AS TagRank
    FROM TopTagsPerUser
),
UserPrimaryTags AS (
    SELECT UserId, Tag, TagCount
    FROM UserTopTagRanks
    WHERE TagRank = 1
),
CombinedData AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
        ua.QuestionsInWindow, ua.AnswersInWindow, ua.CommentCount, ua.AvgPostScore,
        COALESCE(ptt.Tag, '[None]') AS PrimaryTag,
        COALESCE(pts.TagCount, 0) AS PrimaryTagCount,
        COALESCE(pas.AcceptedAnswerScore, 0) AS AvgAcceptedAnswerScore,
        pci.CloseReasonId,
        gravel.UniqueForums
    FROM
        Users u
        LEFT JOIN UserBadgeStats ub ON ub.UserId = u.Id
        LEFT JOIN UserActivityWindow ua ON ua.UserId = u.Id
        LEFT JOIN UserPrimaryTags ptt ON ptt.UserId = u.Id
        LEFT JOIN (
            SELECT UserId, AVG(Score) AS AcceptedAnswerScore
            FROM Posts p
            WHERE p.PostTypeId = 2
            GROUP BY UserId
        ) pas ON pas.UserId = u.Id
        LEFT JOIN PostCloseInfo pci ON pci.PostId IN (
            SELECT p.Id FROM Posts p WHERE p.OwnerUserId = u.Id
        )
        LEFT JOIN (
            SELECT
                ul.UserId,
                COUNT(DISTINCT pl.PostId) AS UniqueForums
            FROM Votes ul
            JOIN Posts pl ON ul.PostId = pl.Id
            GROUP BY ul.UserId
        ) AS gravel ON gravel.UserId = u.Id
        LEFT JOIN UserPrimaryTags pts ON pts.UserId = u.Id AND pts.Tag = ptt.Tag
),
FinalRankedUsers AS (
    SELECT
        *,
        NTILE(10) OVER (ORDER BY Reputation DESC NULLS LAST) AS ReputationDecile,
        CASE WHEN (GoldBadges + SilverBadges + BronzeBadges) > 50 THEN 'Veteran'
             WHEN (GoldBadges + SilverBadges + BronzeBadges) BETWEEN 10 AND 50 THEN 'Experienced'
             ELSE 'Rookie' END AS UserLevel,
        (AnswersInWindow::float / NULLIF(QuestionsInWindow,0)) AS AnswerToQuestionRatio,
        CONCAT(
            COALESCE(DisplayName,'<Anonymous>'),
            ' (#', Id, ') Score: ',
            COALESCE(CAST(ROUND(AvgPostScore,2) AS varchar),'0'),
            ', Tags[', PrimaryTag, ':', PrimaryTagCount::text, ']'
        ) AS DisplaySummary,
        GREATEST(COALESCE(AvgAcceptedAnswerScore, 0), 0) AS SafeAvgAcceptedAnswerScore
    FROM CombinedData
)
SELECT
    fru.UserId,
    fru.DisplayName,
    fru.Reputation,
    fru.UserLevel,
    fru.GoldBadges,
    fru.SilverBadges,
    fru.BronzeBadges,
    fru.QuestionsInWindow,
    fru.AnswersInWindow,
    fru.CommentCount,
    fru.UpVotesGiven,
    fru.DownVotesGiven,
    fru.PrimaryTag,
    fru.PrimaryTagCount,
    fru.AnswerToQuestionRatio,
    fru.DisplaySummary,
    fru.SafeAvgAcceptedAnswerScore,
    CASE WHEN fru.CloseReasonId IS NOT NULL THEN 'Closed' ELSE 'Open' END AS CloseStatus,
    fru.ReputationDecile,
    RANK() OVER (PARTITION BY fru.UserLevel ORDER BY fru.Reputation DESC) AS LevelRank,
    COUNT(*) OVER (PARTITION BY fru.UserLevel) AS LevelSize
FROM
    FinalRankedUsers fru
WHERE fru.Reputation >= 1000 
  AND COALESCE(fru.AnswersInWindow,0) >= 10
ORDER BY
    fru.UserLevel,
    fru.LevelRank,
    fru.Reputation DESC;
