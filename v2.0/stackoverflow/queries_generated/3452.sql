-- {"query": "3452.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2346} 

/*  Complex benchmark query using CTEs, window functions, outer joins,
    correlated subqueries, set operators, string handling and NULL logic   */
WITH
/*--------------------------------------------------------------
    per‑user statistics (reputation, votes, badges, post counts)
----------------------------------------------------------------*/
UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0) AS NetVotes,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
        (SELECT MAX(CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastPostDate
    FROM Users u
),

/*--------------------------------------------------------------
    per‑tag usage statistics (derived from Posts.Tags)
----------------------------------------------------------------*/
TagStats AS (
    SELECT
        t.TagName,
        t.Count            AS TagUseCount,
        COALESCE(t.IsModeratorOnly,0) AS IsModOnly,
        COALESCE(t.IsRequired,0)      AS IsRequired,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS PostsWithTag
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),

/*--------------------------------------------------------------
    recent activity per user (votes, comments, posts)
----------------------------------------------------------------*/
RecentActivity AS (
    SELECT
        u.Id                                               AS UserId,
        MAX(v.CreationDate)                                AS LastVoteDate,
        MAX(c.CreationDate)                                AS LastCommentDate,
        MAX(p.CreationDate)                                AS LastPostActivityDate
    FROM Users u
    LEFT JOIN Votes    v ON v.UserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),

/*--------------------------------------------------------------
    ranking of users by reputation and badge weight
----------------------------------------------------------------*/
TopUsers AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.NetVotes,
        us.GoldBadges,
        us.SilverBadges,
        us.BronzeBadges,
        us.QuestionCount,
        us.AnswerCount,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.NetVotes DESC)                     AS RepRank,
        ROW_NUMBER() OVER (ORDER BY (us.GoldBadges*100 + us.SilverBadges*10 + us.BronzeBadges) DESC) AS BadgeRank
    FROM UserStats us
)

/*====================================================================
   Final result set:
   – detailed rows for the top 200 users
   – a summary row appended with UNION ALL
====================================================================*/
SELECT
    tu.Id,
    tu.DisplayName,
    tu.Reputation,
    tu.NetVotes,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.RepRank,
    tu.BadgeRank,
    COALESCE(ra.LastVoteDate, ra.LastCommentDate, ra.LastPostActivityDate) AS LastActivity,
    CASE
        WHEN tu.RepRank <= 10  THEN 'Top10'
        WHEN tu.RepRank <= 100 THEN 'Top100'
        ELSE 'Other'
    END AS RankBucket,
    COALESCE(ts.TagName, 'NoTagMatch')               AS SampleTag,
    COALESCE(ts.PostsWithTag,0)                      AS TagPostCount
FROM TopUsers tu
LEFT JOIN RecentActivity ra ON ra.UserId = tu.Id
LEFT JOIN (
    SELECT TagName, PostsWithTag
    FROM TagStats
    ORDER BY PostsWithTag DESC
    FETCH FIRST 1 ROW ONLY
) ts ON TRUE                                 -- scalar sub‑query turned into a cross‑join
WHERE tu.RepRank <= 200

UNION ALL

SELECT
    NULL                                          AS Id,
    'Aggregate Summary'                           AS DisplayName,
    NULL                                          AS Reputation,
    NULL                                          AS NetVotes,
    SUM(tu.GoldBadges)                            AS GoldBadges,
    SUM(tu.SilverBadges)                          AS SilverBadges,
    SUM(tu.BronzeBadges)                          AS BronzeBadges,
    SUM(tu.QuestionCount)                         AS QuestionCount,
    SUM(tu.AnswerCount)                           AS AnswerCount,
    NULL                                          AS RepRank,
    NULL                                          AS BadgeRank,
    MAX(COALESCE(ra.LastVoteDate, ra.LastCommentDate, ra.LastPostActivityDate)) AS LastActivity,
    NULL                                          AS RankBucket,
    NULL                                          AS SampleTag,
    NULL                                          AS TagPostCount
FROM TopUsers tu
LEFT JOIN RecentActivity ra ON ra.UserId = tu.Id
WHERE tu.RepRank <= 200
ORDER BY RepRank ASC NULLS LAST;
