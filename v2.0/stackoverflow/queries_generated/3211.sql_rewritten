-- {"query": "3211.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2268} 
WITH
    -- 1️⃣ Top active users with reputation, voting activity and badge counts
    TopUsers AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COUNT(p.Id)                                    AS TotalPosts,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
            COUNT(b.Id) FILTER (WHERE b.Class = 1)          AS GoldBadgeCount,
            ROW_NUMBER() OVER (ORDER BY SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) DESC) AS rn
        FROM Users u
        LEFT JOIN Posts  p ON p.OwnerUserId = u.Id
        LEFT JOIN Votes  v ON v.UserId = u.Id
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
        HAVING COUNT(p.Id) > 0
    ),

    -- 2️⃣ Most recent closed question per user (correlated sub‑query inside a CTE)
    RecentClosedQuestions AS (
        SELECT
            p.Id,
            p.Title,
            p.CreationDate,
            p.ClosedDate,
            p.OwnerUserId,
            STRING_TO_ARRAY( TRIM(BOTH '<>' FROM p.Tags), '><' ) AS TagArray,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ClosedDate DESC) AS rn_user
        FROM Posts p
        WHERE p.PostTypeId = 1               -- Question
          AND p.ClosedDate IS NOT NULL
    ),

    -- 3️⃣ Tag‑level statistics, using window functions and aggregation
    TagStats AS (
        SELECT
            t.TagName,
            COUNT(p.Id)                                           AS QuestionCount,
            AVG(p.Score)::NUMERIC(10,2)                           AS AvgScore,
            MAX(p.ViewCount)                                      AS MaxViews,
            STRING_AGG(DISTINCT u.DisplayName, ', ') FILTER (WHERE u.Reputation > 20000) AS TopHighRepUsers,
            RANK() OVER (ORDER BY COUNT(p.Id) DESC)               AS TagRank
        FROM Tags t
        JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
        JOIN Users u ON u.Id = p.OwnerUserId
        WHERE p.PostTypeId = 1
        GROUP BY t.TagName
        HAVING COUNT(p.Id) > 5
    ),

    -- 4️⃣ Badge hierarchy – correlated scalar sub‑queries
    BadgeHierarchy AS (
        SELECT
            b.Id,
            b.UserId,
            b.Name,
            b.Class,
            (SELECT COUNT(*) FROM Badges b2 WHERE b2.UserId = b.UserId AND b2.Class < b.Class) AS LowerClassCount,
            (SELECT MAX(b3.Class) FROM Badges b3 WHERE b3.UserId = b.UserId)                     AS MaxClassForUser
        FROM Badges b
    ),

    -- 5️⃣ Combined per‑user view using LATERAL joins for the most recent closed question
    UserDetail AS (
        SELECT
            tu.Id                                    AS UserId,
            tu.DisplayName,
            tu.Reputation,
            tu.TotalPosts,
            tu.UpVoteCount,
            tu.DownVoteCount,
            tu.GoldBadgeCount,
            rcq.Id                                   AS RecentClosedQuestionId,
            rcq.Title                                AS RecentClosedQuestionTitle,
            rcq.ClosedDate,
            rcq.TagArray,
            bh.Name                                  AS BadgeName,
            bh.Class                                 AS BadgeClass,
            bh.LowerClassCount,
            bh.MaxClassForUser
        FROM TopUsers tu
        LEFT JOIN LATERAL (
            SELECT *
            FROM RecentClosedQuestions rcq
            WHERE rcq.OwnerUserId = tu.Id AND rcq.rn_user = 1
        ) rcq ON TRUE
        LEFT JOIN BadgeHierarchy bh ON bh.UserId = tu.Id
        WHERE tu.rn <= 100               -- limit to top 100 users by up‑votes
    )

-- 6️⃣ Final result set: union of user‑centric rows and a set‑operator block for “neglected” low‑score questions
SELECT
    ud.UserId,
    ud.DisplayName,
    ud.Reputation,
    ud.TotalPosts,
    ud.UpVoteCount,
    ud.DownVoteCount,
    ud.GoldBadgeCount,
    ud.RecentClosedQuestionId,
    ud.RecentClosedQuestionTitle,
    ud.ClosedDate,
    ts.TagName,
    ts.QuestionCount,
    ts.AvgScore,
    ts.MaxViews,
    ts.TopHighRepUsers,
    ud.BadgeName,
    ud.BadgeClass,
    ud.LowerClassCount,
    ud.MaxClassForUser
FROM UserDetail ud
LEFT JOIN LATERAL (
    SELECT *
    FROM TagStats ts
    WHERE ts.TagName = ANY (ud.TagArray)
    ORDER BY ts.QuestionCount DESC
    LIMIT 1
) ts ON TRUE

UNION ALL

SELECT
    NULL AS UserId,
    NULL AS DisplayName,
    NULL AS Reputation,
    NULL AS TotalPosts,
    NULL AS UpVoteCount,
    NULL AS DownVoteCount,
    NULL AS GoldBadgeCount,
    q.Id AS RecentClosedQuestionId,
    q.Title AS RecentClosedQuestionTitle,
    q.CreationDate AS ClosedDate,
    NULL AS TagName,
    NULL AS QuestionCount,
    NULL AS AvgScore,
    NULL AS MaxViews,
    NULL AS TopHighRepUsers,
    NULL AS BadgeName,
    NULL AS BadgeClass,
    NULL AS LowerClassCount,
    NULL AS MaxClassForUser
FROM Posts q
WHERE q.PostTypeId = 1                     -- Question
  AND q.Score < 0
  AND NOT EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2)   -- no up‑votes
ORDER BY UpVoteCount DESC NULLS LAST, RecentClosedQuestionTitle
LIMIT 10;