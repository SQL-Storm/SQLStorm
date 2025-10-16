-- {"query": "5058.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1344} 
WITH RecentPosts AS (
    SELECT 
        p.*,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.CreationDate >= NOW() - INTERVAL '60 days'
),
TopUsers AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= NOW() - INTERVAL '365 days'
    WHERE u.CreationDate <= NOW() - INTERVAL '90 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeCounts AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    WHERE b.Date >= NOW() - INTERVAL '2 years'
    GROUP BY b.UserId
),
UserComments AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.CreationDate >= NOW() - INTERVAL '180 days'
    GROUP BY c.UserId
),
VotesAgg AS (
    SELECT
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        COUNT(*) AS TotalVotesGiven
    FROM Votes v
    WHERE v.CreationDate >= NOW() - INTERVAL '180 days'
    GROUP BY v.UserId
),
RecentAcceptedAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId AS AskerId,
        a.OwnerUserId AS AnswererId,
        a.Id AS AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        a.CreationDate AS AcceptedAnswerDate,
        q.CreationDate AS QuestionDate,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 AS HoursToAccepted
    FROM Posts q
    JOIN Posts a ON q.AcceptedAnswerId = a.Id
    WHERE q.PostTypeId = 1 AND q.CreationDate >= NOW() - INTERVAL '90 days'
      AND a.CreationDate IS NOT NULL
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.PostCount,
    tu.ReputationRank,
    COALESCE(bc.GoldBadges, 0) AS GoldBadges,
    COALESCE(bc.SilverBadges, 0) AS SilverBadges,
    COALESCE(bc.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(bc.TotalBadges, 0) AS BadgeTotal,
    COALESCE(uc.CommentCount, 0) AS CommentCount,
    ROUND(COALESCE(uc.AvgCommentLength, 0), 2) AS AvgCommentLength,
    uc.LastCommentDate,
    COALESCE(va.UpVotesGiven, 0) AS UpVotesGiven,
    COALESCE(va.DownVotesGiven, 0) AS DownVotesGiven,
    COALESCE(va.TotalVotesGiven, 0) AS TotalVotesGiven,
    rp.Id AS MostRecentPostId,
    rp.Title AS MostRecentPostTitle,
    rp.CreationDate AS MostRecentPostDate,
    (
        SELECT COUNT(1) 
        FROM Posts p2
        WHERE p2.OwnerUserId = tu.UserId AND p2.PostTypeId = 2 
            AND p2.CreationDate >= NOW() - INTERVAL '30 days'
    ) AS AnswersPast30Days,
    (
        SELECT STRING_AGG(tn.TagName, ', ')
        FROM (
            SELECT DISTINCT 
                substring(unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')), 1, 35) AS TagName
            FROM Posts p
            WHERE p.OwnerUserId = tu.UserId 
              AND p.PostTypeId = 1 
              AND p.CreationDate >= NOW() - INTERVAL '365 days'
              AND p.Tags IS NOT NULL
        ) AS tn
    ) AS TagsUsedPastYear,
    CASE 
        WHEN tu.Reputation > 5000 AND COALESCE(bc.GoldBadges,0) > 5 THEN 'Legend'
        WHEN tu.Reputation > 1000 THEN 'Experienced'
        ELSE 'Rookie'
    END AS UserLevel,
    (
        SELECT 
            COUNT(DISTINCT raa.QuestionId)
        FROM RecentAcceptedAnswers raa
        WHERE raa.AnswererId = tu.UserId AND raa.HoursToAccepted <= 24
    ) AS FastAcceptedAnswers24h,
    (
        SELECT 
            ROUND(AVG(raa.HoursToAccepted),2)
        FROM RecentAcceptedAnswers raa
        WHERE raa.AnswererId = tu.UserId
    ) AS AvgHoursToAccepted
FROM TopUsers tu
LEFT JOIN BadgeCounts bc ON bc.UserId = tu.UserId
LEFT JOIN UserComments uc ON uc.UserId = tu.UserId
LEFT JOIN VotesAgg va ON va.UserId = tu.UserId
LEFT JOIN RecentPosts rp ON rp.OwnerUserId = tu.UserId AND rp.rn = 1
WHERE tu.PostCount >= 10
  AND (
      tu.Reputation > 2000 
      OR COALESCE(bc.GoldBadges,0) > 2
      OR COALESCE(va.UpVotesGiven, 0) > 100
  )
ORDER BY tu.Reputation DESC, BadgeTotal DESC
LIMIT 100;