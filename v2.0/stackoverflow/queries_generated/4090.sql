-- {"query": "4090.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1366} 
WITH PostEngagement AS (
    SELECT
        p.Id AS PostId,
        pt.Name AS PostType,
        COALESCE(p.Score, 0) AS Score,
        COALESCE(p.ViewCount, 0) AS ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        COALESCE(v.VoteCount, 0) AS VoteCount,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 1
            ELSE 0
        END AS IsClosed,
        ROW_NUMBER() OVER(ORDER BY COALESCE(p.Score, 0) DESC) AS ScoreRank,
        DENSE_RANK() OVER(PARTITION BY pt.Name ORDER BY COALESCE(p.ViewCount, 0) DESC) AS ViewRankByType,
        LAG(COALESCE(p.CreationDate, '1970-01-01'), 1, '1970-01-01') OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostDate
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN (
        SELECT PostId, COUNT(Id) AS VoteCount
        FROM Votes
        WHERE VoteTypeId IN (2, 3) -- UpVotes and DownVotes
        GROUP BY PostId
    ) AS v ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT ph.Id) AS PostHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 1 THEN 1 ELSE 0 END) AS InitialEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS SubsequentEdits,
        AVG(DATEDIFF(minute, u.CreationDate, p.CreationDate)) AS AvgTimeToFirstPost
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory AS ph ON u.Id = ph.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count AS TagPostCount,
        COUNT(DISTINCT pl.PostId) AS DuplicateLinkCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount
    FROM Tags AS t
    LEFT JOIN Posts AS p ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN PostLinks AS pl ON t.Id = pl.LinkTypeId AND pl.LinkTypeId = 3 -- Only consider duplicate links
    GROUP BY t.TagName, t.Count
)
SELECT
    pe.PostId,
    pe.PostType,
    pe.Score,
    pe.ViewCount,
    pe.AnswerCount,
    pe.CommentCount,
    pe.FavoriteCount,
    pe.VoteCount,
    pe.IsClosed,
    pe.ScoreRank,
    pe.ViewRankByType,
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.PostHistoryEvents,
    ua.InitialEdits,
    ua.SubsequentEdits,
    ua.AvgTimeToFirstPost,
    tp.TagName,
    tp.TagPostCount,
    tp.DuplicateLinkCount,
    tp.QuestionCount,
    -- Complex calculation involving string manipulation and date logic
    CASE
        WHEN pe.PostType = 'Question' AND tp.TagName IS NOT NULL THEN
            UPPER(SUBSTRING(tp.TagName, 1, 1)) || LOWER(SUBSTRING(tp.TagName, 2)) || ' - ' ||
            CAST(DATEDIFF(day, pe.PreviousPostDate, COALESCE(p_latest.LastActivityDate, '1970-01-01')) AS VARCHAR) || ' days since last post'
        ELSE 'N/A'
    END AS TaggedPostInfo,
    -- NULL logic and set operator
    COALESCE(u.Location, 'Unknown Location') AS UserLocation,
    COALESCE(u.WebsiteUrl, 'No Website') AS UserWebsite,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pe.PostId AND c.UserId IS NULL) AS AnonymousComments,
    (
        SELECT COUNT(*)
        FROM PostHistory ph
        WHERE ph.PostId = pe.PostId AND ph.PostHistoryTypeId IN (10, 11) -- Closed/Reopened votes
    ) AS CloseReopenVoteCount
FROM PostEngagement AS pe
LEFT JOIN Users AS u ON pe.OwnerUserId = u.Id -- Assuming OwnerUserId is implicitly available or joined via Posts
LEFT JOIN Posts AS p_latest ON pe.PostId = p_latest.Id -- Join to get latest post details
LEFT JOIN UserActivity AS ua ON pe.OwnerUserId = ua.UserId
LEFT JOIN TagPopularity AS tp ON tp.TagName IN (SELECT value FROM STRING_SPLIT(REPLACE(REPLACE(pe.Tags, '<', ''), '>', ''), ' '))
WHERE pe.Score > 0 OR pe.ViewCount > 1000
UNION ALL
SELECT
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
FROM Users
WHERE NOT EXISTS (SELECT 1 FROM Posts WHERE OwnerUserId = Users.Id);