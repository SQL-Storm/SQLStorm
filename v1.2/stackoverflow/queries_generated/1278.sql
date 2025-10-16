-- {"query": "1278.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1300} 

WITH RecursiveCTE AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        u.DisplayName AS OwnerName,
        u.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
    UNION ALL
    SELECT
        ph.PostId,
        p.PostTypeId,
        ph.CreationDate,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0),
        u.DisplayName,
        u.Reputation,
        rc.rn + 1
    FROM PostHistory ph
    INNER JOIN RecursiveCTE rc ON ph.PostId = rc.Id
    INNER JOIN Posts p ON ph.PostId = p.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE ph.PostHistoryTypeId = 5 -- Edit Body
    AND rc.rn < 2
), FilteredPosts AS (
    SELECT * FROM RecursiveCTE WHERE rn = 1
), VotesAgg AS (
    SELECT v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS FavoriteVotes
    FROM Votes v
    GROUP BY v.PostId
), CommentsAgg AS (
    SELECT c.PostId,
        COUNT(*) AS CommentCount,
        MAX(c.CreationDate) AS LastCommentDate,
        STRING_AGG(DISTINCT COALESCE(c.UserDisplayName, 'Anonymous'), ', ') AS Commenters
    FROM Comments c
    GROUP BY c.PostId
), BadgeRanked AS (
    SELECT 
        b.UserId,
        b.Name,
        b.Class,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Class ASC, b.Date DESC) AS rn
    FROM Badges b
)
SELECT
    fp.Id AS PostId,
    pt.Name AS PostType,
    fp.CreationDate,
    fp.Score,
    fp.ViewCount,
    fp.AnswerCount,
    fp.OwnerName,
    fp.OwnerReputation,
    COALESCE(va.UpVotes, 0) AS UpVotes,
    COALESCE(va.DownVotes, 0) AS DownVotes,
    COALESCE(va.FavoriteVotes, 0) AS FavoriteVotes,
    COALESCE(ca.CommentCount, 0) AS CommentCount,
    ca.LastCommentDate,
    CASE 
        WHEN LENGTH(fp.OwnerName) > 0 AND fp.OwnerName IS NOT NULL THEN
            UPPER(SUBSTRING(fp.OwnerName, 1, 1)) || LOWER(SUBSTRING(fp.OwnerName, 2, LENGTH(fp.OwnerName)))
        ELSE 'Unknown'
    END AS FormattedOwnerName,
    -- Extract first tag if available
    CASE 
        WHEN fp.Id IN (SELECT Id FROM Posts WHERE Tags IS NOT NULL AND Tags LIKE '%<%>%' ) THEN
             substring(
               substring(Tags FROM 2 FOR char_length(Tags) - 2)
               FROM 1 FOR POSITION('><' IN substring(Tags FROM 2 FOR char_length(Tags) - 2)) - 1
             )
        ELSE NULL
    END AS FirstTag,
    -- Correlated subquery: find title length differences between accepted answer and question
    (SELECT abs(LENGTH(a.Title) - LENGTH(fp.Title)) FROM Posts a WHERE a.Id = fp.AcceptedAnswerId) AS TitleLengthDiff,
    -- Badge of highest class (gold=1) last awarded to owner user
    (SELECT br.Name FROM BadgeRanked br WHERE br.UserId = fp.OwnerUserId AND br.rn = 1) AS TopBadgeName,
	-- Null-protected complex conditional for detecting hot posts with comment involvement
	CASE 
		WHEN fp.Score > 10 AND COALESCE(ca.CommentCount,0) > 5 
			AND fp.LastActivityDate > fp.CreationDate + interval '7 days' THEN 'Hot with comments'
		WHEN fp.Score > 10 THEN 'Hot'
		WHEN COALESCE(ca.CommentCount,0) > 5 THEN 'Popular with comments'
		ELSE 'Normal' 
	END AS PostPopularityLabel
FROM FilteredPosts fp
INNER JOIN PostTypes pt ON pt.Id = fp.PostTypeId
LEFT JOIN VotesAgg va ON va.PostId = fp.Id
LEFT JOIN CommentsAgg ca ON ca.PostId = fp.Id
WHERE 
    (fp.CreationDate BETWEEN '2018-01-01' AND '2020-12-31')
    AND (fp.Score IS NOT NULL AND fp.Score >= 0)
    AND (
        (fp.OwnerReputation > 1000 OR (fp.Score + COALESCE(va.UpVotes,0) - COALESCE(va.DownVotes,0)) > 5) 
        OR fp.PostTypeId = 2
    )
ORDER BY fp.CreationDate DESC
LIMIT 100
UNION
SELECT
    p.Id,
    pt.Name,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    COALESCE(p.AnswerCount, 0),
    u.DisplayName,
    u.Reputation,
    0,
    0,
    0,
    0,
    NULL,
    NULL,
    NULL,
    'NoStats'
FROM Posts p
INNER JOIN PostTypes pt ON pt.Id = p.PostTypeId
LEFT JOIN Users u ON u.Id = p.OwnerUserId
WHERE p.CreationDate > CURRENT_DATE - interval '30 days'
  AND p.Id NOT IN (SELECT Id FROM FilteredPosts)
ORDER BY 1 DESC
LIMIT 20;
