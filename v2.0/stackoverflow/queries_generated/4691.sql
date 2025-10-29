-- {"query": "4691.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1009} 

WITH RankedPostHistory AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.UserId,
        ph.CreationDate,
        p.PostTypeId,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) AND p.PostTypeId IN (1, 2)
),
RecentEdits AS (
    SELECT
        PostId,
        UserId,
        CreationDate,
        PostTypeId,
        OwnerUserId,
        AcceptedAnswerId,
        ParentId
    FROM RankedPostHistory
    WHERE rn = 1
),
UserEditStats AS (
    SELECT
        re.UserId,
        COUNT(re.PostId) AS EditCount,
        AVG(DATEDIFF(day, p.CreationDate, re.CreationDate)) AS AvgDaysToEdit,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionEdits,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerEdits
    FROM RecentEdits re
    JOIN Posts p ON re.PostId = p.Id
    GROUP BY re.UserId
),
PotentialSpamUsers AS (
    SELECT
        u.Id AS UserId,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVoteCount,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
        COUNT(DISTINCT ph.PostId) AS EditedPostCount
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (5, 8) -- Edits and Rollbacks
    WHERE u.Reputation < 500
    GROUP BY u.Id
    HAVING COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) > COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) * 3
       AND COUNT(DISTINCT ph.PostId) > 10
)
SELECT
    COALESCE(ues.DisplayName, 'Deleted User') AS EditorDisplayName,
    ues.Reputation AS EditorReputation,
    ues.CreationDate AS EditorCreationDate,
    COUNT(DISTINCT ps.Id) AS TotalPosts Edited,
    SUM(CASE WHEN ps.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionEdits,
    SUM(CASE WHEN ps.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerEdits,
    AVG(DATEDIFF(hour, ps.CreationDate, re.CreationDate)) AS AvgHoursToFirstEdit,
    COUNT(CASE WHEN psl.LinkTypeId = 3 THEN 1 END) AS DuplicateLinksCreated,
    COALESCE(CASE WHEN psu.DownVoteCount > psu.UpVoteCount * 2 THEN 'High_Downvote_Ratio' ELSE 'Normal_Ratio' END, 'Unknown') AS UserSpamIndicator,
    MAX(pht.Name) AS LastEditType
FROM Posts ps
JOIN RecentEdits re ON ps.Id = re.PostId
JOIN Users ues ON re.UserId = ues.Id
LEFT JOIN PostLinks psl ON ps.Id = psl.PostId AND psl.LinkTypeId = 3
LEFT JOIN PotentialSpamUsers psu ON re.UserId = psu.UserId
LEFT JOIN PostHistory pht ON ps.Id = pht.PostId AND pht.PostHistoryTypeId IN (4, 5, 6) AND pht.rn = 1 -- Join again to get the actual last edit type name
GROUP BY
    COALESCE(ues.DisplayName, 'Deleted User'),
    ues.Reputation,
    ues.CreationDate,
    CASE WHEN psu.DownVoteCount > psu.UpVoteCount * 2 THEN 'High_Downvote_Ratio' ELSE 'Normal_Ratio' END
HAVING COUNT(DISTINCT ps.Id) > 50
ORDER BY
    EditorReputation DESC,
    TotalPosts Edited DESC,
    DuplicateLinksCreated DESC;
