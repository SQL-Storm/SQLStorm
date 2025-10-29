-- {"query": "3249.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1890}
WITH
UserMetrics AS (
    SELECT
        u.Id                                              AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id)                               AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        SUM(COALESCE(p.Score,0))                           AS TotalScore,
        MAX(u.CreationDate)                               AS AccountCreated,
        MAX(u.LastAccessDate)                             AS LastSeen,
        COUNT(DISTINCT b.Id)                               AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p   ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b  ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

RecentActivity AS (
    SELECT
        ua.UserId,
        MAX(v.CreationDate)   AS LastVoteDate,
        MAX(c.CreationDate)   AS LastCommentDate,
        MAX(ph.CreationDate)  AS LastEditDate
    FROM UserMetrics ua
    LEFT JOIN Votes v       ON v.UserId = ua.UserId
    LEFT JOIN Comments c    ON c.UserId = ua.UserId
    LEFT JOIN PostHistory ph ON ph.UserId = ua.UserId
    GROUP BY ua.UserId
),

TagPerformance AS (
    SELECT
        a.OwnerUserId                                 AS UserId,
        t.TagName,
        COUNT(*)                                      AS AnswersInTag,
        AVG(q.Score)                                  AS AvgQuestionScore,
        ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId
                           ORDER BY AVG(q.Score) DESC) AS TagRank
    FROM Posts a
    JOIN Posts q   ON q.Id = a.ParentId
    JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '<>' FROM q.Tags), '><')) AS TagName
    ) AS t ON TRUE
    WHERE a.PostTypeId = 2
      AND a.OwnerUserId IS NOT NULL
    GROUP BY a.OwnerUserId, t.TagName
),

TopTagPerUser AS (
    SELECT
        tp.UserId,
        tp.TagName,
        tp.AvgQuestionScore,
        tp.AnswersInTag
    FROM TagPerformance tp
    WHERE tp.TagRank = 1
),

InactiveHighRep AS (
    SELECT
        um.UserId,
        um.DisplayName,
        um.Reputation,
        ra.LastVoteDate,
        ra.LastCommentDate,
        ra.LastEditDate,
        CASE
            WHEN ra.LastVoteDate IS NULL THEN 1
            WHEN ra.LastVoteDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days') THEN 1
            ELSE 0
        END AS IsInactive
    FROM UserMetrics um
    LEFT JOIN RecentActivity ra ON ra.UserId = um.UserId
    WHERE um.Reputation > 50000
      AND (ra.LastVoteDate IS NULL OR ra.LastVoteDate < CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days')
      AND um.GoldBadges > 5
),

VoteStatsByType AS (
    SELECT
        pt.Name                               AS PostType,
        vt.Name                               AS VoteType,
        COUNT(v.Id)                           AS VoteCount,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    JOIN Posts p      ON p.Id = v.PostId
    JOIN PostTypes pt ON pt.Id = p.PostTypeId
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY pt.Name, vt.Name
),

VoteStatsSummary AS (
    SELECT
        PostType,
        SUM(VoteCount)                AS TotalVotes,
        SUM(UpVotes)                  AS TotalUp,
        SUM(DownVotes)                AS TotalDown
    FROM VoteStatsByType
    GROUP BY PostType
),

AllHighRepUsers AS (
    SELECT
        ihr.UserId,
        ihr.DisplayName,
        ihr.Reputation,
        0 AS InactiveFlag,
        um.TotalPosts,
        um.Questions,
        um.Answers,
        um.TotalScore,
        tt.TagName,
        tt.AvgQuestionScore,
        tt.AnswersInTag
    FROM InactiveHighRep ihr
    JOIN UserMetrics um ON um.UserId = ihr.UserId
    LEFT JOIN TopTagPerUser tt ON tt.UserId = ihr.UserId
    UNION ALL
    SELECT
        um.UserId,
        um.DisplayName,
        um.Reputation,
        1 AS InactiveFlag,
        um.TotalPosts,
        um.Questions,
        um.Answers,
        um.TotalScore,
        tt.TagName,
        tt.AvgQuestionScore,
        tt.AnswersInTag
    FROM UserMetrics um
    LEFT JOIN TopTagPerUser tt ON tt.UserId = um.UserId
    WHERE um.Reputation > 20000
      AND NOT EXISTS (SELECT 1 FROM InactiveHighRep i WHERE i.UserId = um.UserId)
)

SELECT
    ahu.UserId,
    ahu.DisplayName,
    ahu.Reputation,
    ahu.InactiveFlag,
    ahu.TotalPosts,
    ahu.Questions,
    ahu.Answers,
    ahu.TotalScore,
    COALESCE(ahu.TagName, 'N/A')                         AS TopTag,
    ROUND(COALESCE(ahu.AvgQuestionScore,0),2)           AS AvgQScoreForTag,
    ahu.AnswersInTag,
    RANK() OVER (ORDER BY ahu.Reputation DESC)         AS ReputationRank,
    ROW_NUMBER() OVER (PARTITION BY ahu.InactiveFlag
                       ORDER BY ahu.TotalScore DESC)  AS ScoreRankWithinGroup,
    CASE
        WHEN ahu.InactiveFlag = 1 THEN 'Inactive'
        ELSE 'Active'
    END                                                AS ActivityStatus,
    COALESCE(
        (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.UserId = ahu.UserId),
        (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.UserId = ahu.UserId)
    )                                                   AS LastEngagementDate,
    (ahu.Reputation * 0.6
     + ahu.TotalScore * 0.3
     + (CASE WHEN ahu.InactiveFlag = 0 THEN 1000 ELSE 0 END)) AS WeightedScore
FROM AllHighRepUsers ahu
ORDER BY ahu.Reputation DESC
LIMIT 100;