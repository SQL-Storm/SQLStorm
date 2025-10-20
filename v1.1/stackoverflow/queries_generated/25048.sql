-- {"query": "25048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2343} 

WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteSum,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteSum,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*) AS TotalBadges,
        COUNT(*) FILTER (WHERE b.Class = 1) AS Gold,
        COUNT(*) FILTER (WHERE b.Class = 2) AS Silver,
        COUNT(*) FILTER (WHERE b.Class = 3) AS Bronze,
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),
TopTagActivity AS (
    SELECT 
        t.TagName,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) DESC) AS rn
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY t.TagName
),
RecentClosedDuplicates AS (
    SELECT 
        ph.PostId,
        ph.CreationDate AS ClosedDate,
        CAST(ph.Comment AS INT) AS DuplicateOfPostId,
        p.Title AS ClosedTitle,
        dup.Title AS DuplicateTitle,
        DENSE_RANK() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rk
    FROM PostHistory ph
    JOIN Posts p ON p.Id = ph.PostId
    LEFT JOIN Posts dup ON dup.Id = CAST(ph.Comment AS INT)
    WHERE ph.PostHistoryTypeId = 10                     -- Close
      AND ph.Comment ~ '^\d+$'                         -- comment is numeric (duplicate target)
      AND EXISTS (
          SELECT 1 FROM PostHistory ph2
          WHERE ph2.PostId = ph.PostId
            AND ph2.PostHistoryTypeId = 33            -- PostNoticeAdded (duplicate notice)
      )
),
UserPerformance AS (
    SELECT 
        us.Id,
        us.DisplayName,
        us.Reputation,
        us.QuestionCount,
        us.AnswerCount,
        us.UpVoteSum - us.DownVoteSum AS NetVotes,
        COALESCE(bs.TotalBadges,0) AS TotalBadges,
        bs.Gold,
        bs.Silver,
        bs.Bronze,
        bs.BadgeList,
        ROW_NUMBER() OVER (ORDER BY (us.Reputation + (us.UpVoteSum - us.DownVoteSum)) DESC) AS RankOverall,
        AVG(us.LastPostDate) OVER (PARTITION BY DATE_TRUNC('year', us.LastPostDate)) AS AvgLastPostYear
    FROM UserStats us
    LEFT JOIN BadgeStats bs ON bs.UserId = us.Id
    WHERE us.QuestionCount > 0 OR us.AnswerCount > 0
)
SELECT 
    up.Id,
    up.DisplayName,
    up.Reputation,
    up.QuestionCount,
    up.AnswerCount,
    up.NetVotes,
    up.TotalBadges,
    up.Gold,
    up.Silver,
    up.Bronze,
    up.BadgeList,
    up.RankOverall,
    up.AvgLastPostYear,
    CASE 
        WHEN up.RankOverall <= 10 THEN 'Elite'
        WHEN up.RankOverall <= 100 THEN 'Pro'
        ELSE 'Member'
    END AS Tier,
    STRING_AGG(DISTINCT tt.TagName, '; ') FILTER (WHERE tt.rn <= 5) AS TopTags
FROM UserPerformance up
LEFT JOIN LATERAL (
    SELECT t.TagName, t.rn
    FROM TopTagActivity t
    WHERE EXISTS (
        SELECT 1 FROM Posts p
        WHERE p.OwnerUserId = up.Id
          AND p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    )
    ORDER BY t.rn
    LIMIT 5
) tt ON TRUE
WHERE up.RankOverall <= 500
GROUP BY 
    up.Id, up.DisplayName, up.Reputation, up.QuestionCount, up.AnswerCount,
    up.NetVotes, up.TotalBadges, up.Gold, up.Silver, up.Bronze,
    up.BadgeList, up.RankOverall, up.AvgLastPostYear, up.Tier
UNION ALL
SELECT NULL, '---', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM (SELECT 1) dummy
ORDER BY RankOverall NULLS LAST
LIMIT 1000;
