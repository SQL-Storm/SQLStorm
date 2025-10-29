-- {"query": "3209.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2024}
WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, '(no location)') AS Location,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score END) AS AvgPostScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(p.LastActivityDate) AS LastActivity,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgeCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadgeCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadgeCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
TagUsage AS (
    -- Split Tags by parsing the angle-bracket delimited string in a dialect-agnostic way
    SELECT
        pu.OwnerUserId AS UserId,
        SUM(CASE WHEN LOWER(tname) LIKE '%sql%' THEN 1 ELSE 0 END) AS SqlTagPosts,
        SUM(CASE WHEN LOWER(tname) LIKE '%performance%' THEN 1 ELSE 0 END) AS PerfTagPosts
    FROM Posts pu
    JOIN (
        -- normalize tags string to comma-separated list and split using a numbers table approach
        SELECT
            p_inner.Id AS PostId,
            NULLIF(TRIM(tag_part), '') AS tname
        FROM (
            SELECT Id, Tags,
                   -- remove leading/trailing angle brackets and replace '><' with ',' for predictable splitting
                   CASE
                     WHEN Tags IS NULL THEN NULL
                     ELSE REPLACE(TRIM(BOTH '<' FROM Tags), '><', ',')
                   END AS norm_tags
            FROM Posts
        ) p_inner
        CROSS JOIN LATERAL (
            -- split by commas using a recursive-like numbers generator via string functions
            SELECT
                CASE
                    WHEN strpos(p_inner.norm_tags, ',') = 0 THEN p_inner.norm_tags
                    ELSE trim(substring(p_inner.norm_tags FROM 1 FOR (CASE WHEN strpos(p_inner.norm_tags, ',')>0 THEN strpos(p_inner.norm_tags, ',')-1 ELSE length(p_inner.norm_tags) END)))
                END AS tag_part,
                CASE
                    WHEN strpos(p_inner.norm_tags, ',') = 0 THEN ''
                    ELSE substring(p_inner.norm_tags FROM (strpos(p_inner.norm_tags, ',')+1))
                END AS rest
            UNION ALL
            SELECT
                CASE
                    WHEN strpos(rest, ',') = 0 THEN rest
                    ELSE trim(substring(rest FROM 1 FOR (CASE WHEN strpos(rest, ',')>0 THEN strpos(rest, ',')-1 ELSE length(rest) END)))
                END AS tag_part,
                CASE
                    WHEN strpos(rest, ',') = 0 THEN ''
                    ELSE substring(rest FROM (strpos(rest, ',')+1))
                END AS rest
            FROM (
                SELECT
                    CASE
                        WHEN strpos(p_inner.norm_tags, ',') = 0 THEN p_inner.norm_tags
                        ELSE trim(substring(p_inner.norm_tags FROM 1 FOR (CASE WHEN strpos(p_inner.norm_tags, ',')>0 THEN strpos(p_inner.norm_tags, ',')-1 ELSE length(p_inner.norm_tags) END)))
                    END AS tag_part,
                    CASE
                        WHEN strpos(p_inner.norm_tags, ',') = 0 THEN ''
                        ELSE substring(p_inner.norm_tags FROM (strpos(p_inner.norm_tags, ',')+1))
                    END AS rest
            ) init
            WHERE init.rest <> ''
        ) split_recursive
        WHERE split_recursive.tag_part IS NOT NULL
    ) split_tags ON split_tags.PostId = pu.Id
    JOIN Tags t ON LOWER(t.TagName) = LOWER(split_tags.tname)
    WHERE pu.OwnerUserId IS NOT NULL
      AND split_tags.tname IS NOT NULL
    GROUP BY pu.OwnerUserId
),
RecentClosedQuestions AS (
    SELECT
        ph.UserId,
        COUNT(*) AS RecentlyClosedCount
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
    WHERE pht.Name = 'Post Closed'
      AND ph.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30 days')
    GROUP BY ph.UserId
),
MainResult AS (
    SELECT
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.Location,
        us.QuestionCount,
        us.AnswerCount,
        ROUND(CAST(us.AvgPostScore AS numeric), 2) AS AvgScore,
        us.UpVoteCount,
        us.DownVoteCount,
        us.GoldBadgeCount,
        us.SilverBadgeCount,
        us.BronzeBadgeCount,
        COALESCE(tu.SqlTagPosts, 0) AS SqlTagPosts,
        COALESCE(tu.PerfTagPosts, 0) AS PerfTagPosts,
        COALESCE(rc.RecentlyClosedCount, 0) AS RecentClosed,
        ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.AnswerCount DESC) AS ReputationRank,
        CASE
            WHEN us.Reputation > 20000 THEN 'Legendary'
            WHEN us.Reputation BETWEEN 10000 AND 20000 THEN 'Expert'
            WHEN us.Reputation BETWEEN 5000 AND 9999 THEN 'Experienced'
            ELSE 'Novice'
        END AS ReputationTier,
        (us.DisplayName || ' (' || us.Id || ')') AS UserLabel,
        (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = us.Id) AS LastPostDate,
        CASE WHEN EXISTS (
            SELECT 1
            FROM Posts p2
            WHERE p2.OwnerUserId = us.Id
              AND p2.PostTypeId = 1
              AND p2.ClosedDate IS NOT NULL
              AND p2.ClosedDate > (CAST('2024-10-01' AS date) - INTERVAL '7 days')
        ) THEN TRUE ELSE FALSE END AS HasRecentlyClosedQuestion
    FROM UserStats us
    LEFT JOIN TagUsage tu ON tu.UserId = us.Id
    LEFT JOIN RecentClosedQuestions rc ON rc.UserId = us.Id
    WHERE us.Reputation > 1000
)
SELECT *
FROM MainResult
ORDER BY Reputation DESC
LIMIT 10;