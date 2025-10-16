-- {"query": "1306.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1359} 

WITH TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Location,
        TotalAnswers = (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2),
        AvgAnswerScore = COALESCE((
            SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2
        ), 0),
        BadgeCounts = (
            SELECT jsonb_object_agg(b.Class, bcount) FROM (
                SELECT
                    b.Class,
                    COUNT(*) AS bcount
                FROM Badges b
                WHERE b.UserId = u.Id
                GROUP BY b.Class
            ) bc
        )
    FROM Users u
    WHERE u.Reputation > 10000
), PostsWithRanks AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS RankPerUser,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalPostsPerUser,
        p.Title,
        p.Tags
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Question or Answer
), UserTopPosts AS (
    SELECT
        pu.Id,
        pu.OwnerUserId,
        pu.PostTypeId,
        pu.CreationDate,
        pu.Score,
        pu.ViewCount,
        pu.AnswerCount,
        pu.Tags,
        pu.Title
    FROM PostsWithRanks pu
    WHERE pu.RankPerUser <= 5
), PostCloseInfo AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS CloseDate,
        cr.Name AS CloseReason
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes cr ON cr.Id = CAST(ph.Comment AS int)
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
), UserMetrics AS (
    SELECT
        tu.Id AS UserId,
        tu.DisplayName,
        tu.Reputation,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END),0) AS Questions,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END),0) AS Answers,
        AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
        MAX(p.ViewCount) AS MaxViewCount,
        COUNT(DISTINCT pc.PostId) AS NumberOfClosedPosts,
        ARRAY_AGG(DISTINCT pc.CloseReason) FILTER (WHERE pc.CloseReason IS NOT NULL) AS CloseReasons,
        STRING_AGG(
            DISTINCT COALESCE(SUBSTRING(tn.TagName FROM 1 FOR 15), '') || '(' || COALESCE(tg.Count::text,'0') || ')',
            ', '
            ORDER BY tg.Count DESC NULLS LAST
        ) AS PopularTagsSummary
    FROM TopUsers tu
    LEFT JOIN Posts p ON p.OwnerUserId = tu.Id
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag
    ) t ON true
    LEFT JOIN Tags tn ON tn.TagName = t.tag
    LEFT JOIN Tags tg ON tg.TagName = tn.TagName
    LEFT JOIN PostCloseInfo pc ON pc.PostId = p.Id
    GROUP BY tu.Id, tu.DisplayName, tu.Reputation
), AnswerWinRanks AS (
    SELECT
        a.Id,
        a.ParentId,
        a.Score,
        a.OwnerUserId,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
), QuestionVotes AS (
    SELECT
        p.Id,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS DownVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END),0) AS BountiesStarted,
        COALESCE(SUM(v.BountyAmount),0) AS TotalBountyAmount
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
)
SELECT
    um.UserId,
    um.DisplayName,
    um.Reputation,
    um.Questions,
    um.Answers,
    ROUND(um.AvgPostScore, 2) AS AvgPostScore,
    um.MaxViewCount,
    um.NumberOfClosedPosts,
    um.CloseReasons,
    um.PopularTagsSummary,
    arr.TopAnswerId,
    arr.TopAnswerScore,
    arr.IsAccepted,
    qv.UpVotes,
    qv.DownVotes,
    qv.BountiesStarted,
    qv.TotalBountyAmount,
    CONCAT_WS(' - ',
            LEFT(utp.Title,50),
            'Score:', utp.Score,
            'Views:', utp.ViewCount,
            'Answers:', COALESCE(utp.AnswerCount,0)
    ) AS SampleTopPostSummary
FROM UserMetrics um
LEFT JOIN LATERAL (
    SELECT a.Id AS TopAnswerId,
           a.Score AS TopAnswerScore,
           CASE WHEN q.AcceptedAnswerId = a.Id THEN TRUE ELSE FALSE END AS IsAccepted
    FROM AnswerWinRanks a
    JOIN Posts q ON q.Id = a.ParentId
    WHERE a.OwnerUserId = um.UserId
    ORDER BY a.AnswerRank
    LIMIT 1
) arr ON TRUE
LEFT JOIN Posts utp ON utp.OwnerUserId = um.UserId
    AND utp.PostTypeId IN (1,2)
    AND utp.Id = (SELECT MAX(Id) FROM Posts p WHERE p.OwnerUserId = um.UserId AND p.PostTypeId IN (1,2))
LEFT JOIN QuestionVotes qv ON qv.Id = utp.Id
ORDER BY um.Reputation DESC NULLS LAST
LIMIT 50;
