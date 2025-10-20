-- {"query": "48077.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 660} 

WITH RankedPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) as rn_score_views,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) as rn_creation,
        ROW_NUMBER() OVER (ORDER BY p.AnswerCount DESC) as rn_answers,
        ROW_NUMBER() OVER (ORDER BY p.CommentCount DESC) as rn_comments
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
),
HighActivityUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Views,
        u.UpVotes,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC) as rn_user_rep_views
    FROM Users u
    WHERE u.Reputation > 10000 AND u.CreationDate < '2020-01-01'
),
RecentEdits AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) as edit_count,
        MAX(ph.CreationDate) as last_edit_date
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY ph.PostId
    HAVING COUNT(ph.Id) > 5
)
SELECT
    rp.Id AS PostId,
    rp.Title AS PostTitle,
    rp.CreationDate AS PostCreationDate,
    rp.Score AS PostScore,
    rp.ViewCount AS PostViewCount,
    rp.AnswerCount AS PostAnswerCount,
    rp.CommentCount AS PostCommentCount,
    hau.DisplayName AS TopUserDisplayName,
    hau.Reputation AS TopUserReputation,
    hau.CreationDate AS TopUserCreationDate,
    re.edit_count AS RecentEditCount,
    re.last_edit_date AS LastRecentEditDate,
    rp.rn_score_views,
    rp.rn_creation,
    rp.rn_answers,
    rp.rn_comments,
    hau.rn_user_rep_views
FROM RankedPosts rp
JOIN HighActivityUsers hau ON rp.rn_score_views <= 100 AND hau.rn_user_rep_views <= 50
LEFT JOIN RecentEdits re ON rp.Id = re.PostId
WHERE rp.rn_score_views BETWEEN 1 AND 100
ORDER BY rp.rn_score_views, hau.rn_user_rep_views;
