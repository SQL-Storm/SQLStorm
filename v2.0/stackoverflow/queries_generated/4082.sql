-- {"query": "4082.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1962} 

WITH PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate AS PostCreationDate,
        COUNT(c.Id) AS CommentCountForPost,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 1
            ELSE 0
        END AS IsClosed,
        CASE
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 1
            ELSE 0
        END AS IsCommunityOwned,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RecentPostOrder
    FROM
        Posts AS p
    LEFT JOIN
        Comments AS c ON p.Id = c.PostId
    LEFT JOIN
        Votes AS v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    GROUP BY
        p.Id, p.OwnerUserId, p.PostTypeId, p.Score, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.CreationDate, p.ClosedDate, p.CommunityOwnedDate
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(b.Date) AS LastBadgeDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UserUpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS UserDownVoteCount,
        COUNT(DISTINCT ph.Id) AS PostHistoryCount,
        MAX(ph.CreationDate) AS LastPostHistoryDate
    FROM
        Users AS u
    LEFT JOIN
        Badges AS b ON u.Id = b.UserId
    LEFT JOIN
        Votes AS v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN
        PostHistory AS ph ON u.Id = ph.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT
        pe.PostId,
        pe.PostTypeId,
        pt.Name AS PostTypeName,
        pe.OwnerUserId,
        ua.DisplayName AS OwnerDisplayName,
        ua.Reputation AS OwnerReputation,
        pe.Score,
        pe.ScoreRank,
        pe.RecentPostOrder,
        pe.AnswerCount,
        pe.CommentCountForPost,
        pe.UpVoteCount,
        pe.DownVoteCount,
        pe.IsClosed,
        pe.IsCommunityOwned,
        CASE
            WHEN pe.Score > 0 THEN 'Positive'
            WHEN pe.Score < 0 THEN 'Negative'
            ELSE 'Neutral'
        END AS ScoreCategory,
        pe.PostCreationDate,
        ua.UserCreationDate AS OwnerAccountCreationDate,
        DATEDIFF(day, ua.UserCreationDate, pe.PostCreationDate) AS DaysSinceOwnerAccountCreation,
        CONCAT(ua.DisplayName, ' (', ua.Reputation, ')') AS OwnerInfo
    FROM
        PostEngagement AS pe
    JOIN
        PostTypes AS pt ON pe.PostTypeId = pt.Id
    LEFT JOIN
        UserActivity AS ua ON pe.OwnerUserId = ua.UserId
    WHERE
        pe.PostTypeId IN (1, 2) -- Questions and Answers only
        AND pe.Score >= -5
        AND pe.PostCreationDate BETWEEN '2023-01-01' AND '2023-12-31'
)
SELECT
    pa.PostId,
    pa.PostTypeName,
    pa.OwnerInfo,
    pa.Score,
    pa.ScoreCategory,
    pa.AnswerCount,
    pa.CommentCountForPost,
    pa.UpVoteCount,
    pa.DownVoteCount,
    pa.IsClosed,
    pa.IsCommunityOwned,
    pa.DaysSinceOwnerAccountCreation,
    ua_last_editor.DisplayName AS LastEditorDisplayName,
    ua_last_editor.Reputation AS LastEditorReputation,
    DATEDIFF(day, pa.PostCreationDate, GETDATE()) AS DaysSinceCreation,
    CASE
        WHEN pa.ScoreRank <= 10 THEN 'Top 10 in Type'
        WHEN pa.RecentPostOrder <= 20 THEN 'Recently Posted'
        ELSE 'Other'
    END AS PostStatusCategory,
    CASE
        WHEN pa.OwnerReputation > 50000 AND pa.Score > 100 THEN 'High Reputation Author, High Score Post'
        WHEN pa.OwnerReputation < 1000 AND pa.Score < 0 THEN 'Low Reputation Author, Negative Score Post'
        ELSE 'Standard Post'
    END AS AuthorScoreProfile,
    COALESCE(pa.OwnerDisplayName, 'Community') AS FinalOwnerDisplayName,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = pa.PostId AND pl.LinkTypeId = 3) AS DuplicateLinkCount
FROM
    PostAnalysis AS pa
LEFT JOIN
    Users AS u_last_editor ON (SELECT ph.UserId FROM PostHistory ph WHERE ph.PostId = pa.PostId AND ph.PostHistoryTypeId IN (4, 5, 6) ORDER BY ph.CreationDate DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY) = u_last_editor.Id
LEFT JOIN
    UserActivity AS ua_last_editor ON u_last_editor.Id = ua_last_editor.UserId
WHERE
    pa.OwnerReputation > 100 OR pa.IsCommunityOwned = 1
UNION ALL
SELECT
    pa.PostId,
    pa.PostTypeName,
    pa.OwnerInfo,
    pa.Score,
    pa.ScoreCategory,
    pa.AnswerCount,
    pa.CommentCountForPost,
    pa.UpVoteCount,
    pa.DownVoteCount,
    pa.IsClosed,
    pa.IsCommunityOwned,
    pa.DaysSinceOwnerAccountCreation,
    ua_last_editor.DisplayName AS LastEditorDisplayName,
    ua_last_editor.Reputation AS LastEditorReputation,
    DATEDIFF(day, pa.PostCreationDate, GETDATE()) AS DaysSinceCreation,
    CASE
        WHEN pa.ScoreRank <= 10 THEN 'Top 10 in Type'
        WHEN pa.RecentPostOrder <= 20 THEN 'Recently Posted'
        ELSE 'Other'
    END AS PostStatusCategory,
    CASE
        WHEN pa.OwnerReputation > 50000 AND pa.Score > 100 THEN 'High Reputation Author, High Score Post'
        WHEN pa.OwnerReputation < 1000 AND pa.Score < 0 THEN 'Low Reputation Author, Negative Score Post'
        ELSE 'Standard Post'
    END AS AuthorScoreProfile,
    COALESCE(pa.OwnerDisplayName, 'Community') AS FinalOwnerDisplayName,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = pa.PostId AND pl.LinkTypeId = 3) AS DuplicateLinkCount
FROM
    PostAnalysis AS pa
LEFT JOIN
    Users AS u_last_editor ON (SELECT ph.UserId FROM PostHistory ph WHERE ph.PostId = pa.PostId AND ph.PostHistoryTypeId IN (4, 5, 6) ORDER BY ph.CreationDate DESC OFFSET 0 ROWS FETCH NEXT 1 ROW ONLY) = u_last_editor.Id
LEFT JOIN
    UserActivity AS ua_last_editor ON u_last_editor.Id = ua_last_editor.UserId
WHERE
    pa.OwnerReputation <= 100 AND pa.IsCommunityOwned = 0
ORDER BY
    pa.Score DESC, pa.PostCreationDate DESC;
