-- {"query": "3451.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1464} 

/* 1️⃣ CTE: basic user metrics */
WITH UserMetrics AS (
    SELECT
        u.Id                                    AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)   AS NetVotes,
        COUNT(p.Id)                              FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id)                              FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        MAX(p.CreationDate)                     AS LastPostDate,
        MAX(p.LastActivityDate)                  AS LastActivityDate,
        COUNT(b.Id)                              AS BadgeCount,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END)  AS GoldBadgeCount,
        STRING_AGG(DISTINCT b.Name, ', ')        FILTER (WHERE b.Class = 1) AS GoldBadgeList,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM Users u
    LEFT JOIN Posts p        ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b       ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),

/* 2️⃣ CTE: recent voting activity (last 30 days) */
RecentVotes AS (
    SELECT
        v.UserId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        COUNT(*)                                      AS TotalVotes,
        MAX(v.CreationDate)                           AS LastVoteDate
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.UserId
),

/* 3️⃣ CTE: tag popularity correlated to the user's questions */
UserTagStats AS (
    SELECT
        u.Id                                 AS UserId,
        t.TagName,
        COUNT(*)                             AS TagUseCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS TagRank
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Tags IS NOT NULL
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(
            TRIM(BOTH '<>' FROM p.Tags), '><'
        )) AS TagName
    ) AS taglist
    JOIN Tags t ON t.TagName = taglist.TagName
    GROUP BY u.Id, t.TagName
),

/* 4️⃣ CTE: high‑reputation users with at least one gold badge */
GoldAchievers AS (
    SELECT
        um.UserId,
        um.DisplayName,
        um.Reputation,
        um.GoldBadgeCount,
        um.GoldBadgeList,
        um.RepRank,
        rv.UpVoteCount,
        rv.DownVoteCount,
        rv.TotalVotes,
        rv.LastVoteDate
    FROM UserMetrics um
    LEFT JOIN RecentVotes rv ON rv.UserId = um.UserId
    WHERE um.GoldBadgeCount > 0
),

/* 5️⃣ CTE: prolific answerers (answer count >= 100) */
ProlificAnswerers AS (
    SELECT
        um.UserId,
        um.DisplayName,
        um.AnswerCount,
        um.NetVotes,
        um.LastActivityDate,
        rv.TotalVotes,
        rv.LastVoteDate
    FROM UserMetrics um
    LEFT JOIN RecentVotes rv ON rv.UserId = um.UserId
    WHERE um.AnswerCount >= 100
)

/* 6️⃣ Final union of two interesting subsets */
SELECT *
FROM (
    SELECT
        ga.UserId,
        ga.DisplayName,
        ga.Reputation,
        ga.GoldBadgeCount,
        ga.GoldBadgeList,
        ga.RepRank,
        ga.UpVoteCount,
        ga.DownVoteCount,
        ga.TotalVotes,
        ga.LastVoteDate,
        'GoldAchiever' AS Category,
        uts.TagName,
        uts.TagUseCount,
        uts.TagRank
    FROM GoldAchievers ga
    LEFT JOIN LATERAL (
        SELECT *
        FROM UserTagStats uts
        WHERE uts.UserId = ga.UserId AND uts.TagRank = 1
    ) uts ON TRUE

    UNION ALL

    SELECT
        pa.UserId,
        pa.DisplayName,
        NULL               AS Reputation,
        NULL               AS GoldBadgeCount,
        NULL               AS GoldBadgeList,
        NULL               AS RepRank,
        pa.UpVoteCount,
        pa.DownVoteCount,
        pa.TotalVotes,
        pa.LastVoteDate,
        'ProlificAnswerer' AS Category,
        uts.TagName,
        uts.TagUseCount,
        uts.TagRank
    FROM ProlificAnswerers pa
    LEFT JOIN LATERAL (
        SELECT *
        FROM UserTagStats uts
        WHERE uts.UserId = pa.UserId AND uts.TagRank = 1
    ) uts ON TRUE
) AS CombinedResults
ORDER BY
    Category,
    COALESCE(Reputation,0) DESC,
    TotalVotes DESC NULLS LAST,
    TagRank ASC;
