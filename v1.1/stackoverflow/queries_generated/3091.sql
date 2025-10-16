-- {"query": "3091.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 737} 
WITH UserReputationStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesReceived,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotesReceived,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 14 THEN 1 ELSE 0 END), 0) AS ModNominationVotes,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScore
    FROM
        Users u
        LEFT JOIN Posts p ON u.Id = p.OwnerUserId
        LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY u.Id, u.DisplayName
),
RecentPostHistory AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
        PostHistory ph
)
SELECT
    ur.UserId,
    ur.DisplayName,
    ur.UpVotesReceived,
    ur.DownVotesReceived,
    ur.ModNominationVotes,
    ur.QuestionCount,
    ur.AnswerCount,
    ur.AvgPostScore,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT c.Id) AS TotalComments,
    MAX(CASE WHEN phh.PostHistoryTypeId IN (4,6,8,10,12,13,14,15,16) AND phh.rn = 1 THEN phh.CreationDate END) AS LastMajorEditDate,
    STRING_AGG(DISTINCT t.TagName, ', ') AS AllTags,
    ARRAY_AGG(DISTINCT cl.Name) AS CloseReasons,
    COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicatesCount
FROM
    UserReputationStats ur
    LEFT JOIN Posts p ON ur.UserId = p.OwnerUserId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN RecentPostHistory phh ON p.Id = phh.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN Tags t ON p.Id = t.WikiPostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (10,11,12,13,14,15,16)
    LEFT JOIN PostHistory ph2 ON ph2.PostId = p.Id AND ph2.PostHistoryTypeId IN (4,6,8,10,12,13,14,15,16) AND ph2.CreationDate > ph.CreationDate
    LEFT JOIN CloseReasonTypes cl ON CAST(ph.Comment AS INTEGER) = cl.Id
WHERE
    ur.UserId IS NOT NULL
GROUP BY
    ur.UserId, ur.DisplayName, ur.UpVotesReceived, ur.DownVotesReceived, ur.ModNominationVotes, ur.QuestionCount, ur.AnswerCount, ur.AvgPostScore
HAVING
    COUNT(p.Id) > 5
ORDER BY
    ur.UserId;