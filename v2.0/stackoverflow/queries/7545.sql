WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_score,
        LAG(p.ViewCount) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_views,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS avg_score_3_posts,
        MAX(p.ViewCount) OVER (PARTITION BY p.OwnerUserId) AS max_views_per_user,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS total_posts_per_user,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Question with Accepted Answer'
            WHEN p.PostTypeId = 1 THEN 'Question without Accepted Answer'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS post_category,
        (p.Title || ' - ' || COALESCE(p.Tags, 'No Tags')) AS title_tag_concat
    FROM Posts p
    WHERE p.CreationDate >= TIMESTAMP '2019-01-01' 
      AND p.CreationDate < TIMESTAMP '2021-01-01'
),
UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS post_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_count,
        SUM(p.Score) AS total_score,
        AVG(p.Score) AS avg_score,
        MAX(p.CreationDate) AS latest_activity,
        STRING_AGG(DISTINCT p.Tags, '; ') AS all_tags_used,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS questions_with_accepted_answers,
        COUNT(DISTINCT CASE WHEN p.CommentCount > 0 THEN p.Id END) AS posts_with_comments,
        RANK() OVER (ORDER BY SUM(p.Score) DESC) AS reputation_rank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= TIMESTAMP '2019-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
ComplexVotesAnalysis AS (
    SELECT 
        v.PostId,
        v.UserId,
        v.VoteTypeId,
        v.CreationDate,
        v.BountyAmount,
        CASE 
            WHEN v.VoteTypeId IN (2, 3) THEN 'Mod Vote'
            WHEN v.VoteTypeId IN (8, 9) THEN 'Bounty Vote'
            ELSE 'Other Vote'
        END AS vote_category,
        ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS vote_rank,
        LAG(v.CreationDate, 1) OVER (PARTITION BY v.PostId ORDER BY v.CreationDate) AS prev_vote_time,
        LEAD(v.VoteTypeId, 1) OVER (PARTITION BY v.PostId ORDER BY v.CreationDate) AS next_vote_type,
        CASE 
            WHEN v.VoteTypeId = 2 AND LAG(v.VoteTypeId, 1) OVER (PARTITION BY v.PostId ORDER BY v.CreationDate) = 3 THEN 'Down-then-Up Vote Pattern'
            WHEN v.VoteTypeId = 3 AND LAG(v.VoteTypeId, 1) OVER (PARTITION BY v.PostId ORDER BY v.CreationDate) = 2 THEN 'Up-then-Down Vote Pattern'
            ELSE 'Normal Vote Pattern'
        END AS vote_pattern,
        EXTRACT(EPOCH FROM (v.CreationDate - LAG(v.CreationDate, 1) OVER (PARTITION BY v.PostId ORDER BY v.CreationDate))) / 60.0 AS minutes_since_prev_vote,
        EXTRACT(EPOCH FROM (v.CreationDate - LAG(v.CreationDate, 1) OVER (PARTITION BY v.UserId ORDER BY v.CreationDate))) / 60.0 AS minutes_since_prev_vote_by_user
    FROM Votes v
    WHERE v.CreationDate >= TIMESTAMP '2019-01-01' 
      AND v.VoteTypeId IN (1, 2, 3, 8, 9)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS tag_frequency,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'High Frequency'
            WHEN t.Count > 500 THEN 'Medium Frequency'
            WHEN t.Count > 100 THEN 'Low Frequency'
            ELSE 'Very Low Frequency'
        END AS frequency_category,
        CASE 
            WHEN t.ExcerptPostId IS NOT NULL THEN 'Has Excerpt'
            WHEN t.WikiPostId IS NOT NULL THEN 'Has Wiki'
            ELSE 'No Content'
        END AS content_status,
        RANK() OVER (ORDER BY t.Count DESC) AS frequency_rank,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) AS previous_frequency
    FROM Tags t
    WHERE t.Count > 25
),
-- replace UNNEST + string_to_array subquery with a derived table that splits tags per post
PostTags AS (
    SELECT
        rp.Id AS PostId,
        trim(tag) AS TagName
    FROM RankedPosts rp,
    LATERAL (
        SELECT value AS tag
        FROM (SELECT regexp_split_to_table(COALESCE(rp.Tags, ''), '<>') AS value) s
    ) split
    WHERE COALESCE(rp.Tags, '') <> ''
)
SELECT 
    COUNT(*) AS total_results,
    COUNT(DISTINCT ra.Id) AS unique_posts_analyzed,
    COUNT(DISTINCT CASE WHEN ra.post_category = 'Question with Accepted Answer' THEN ra.Id END) AS questions_with_accepts,
    COUNT(DISTINCT CASE WHEN ra.post_category = 'Answer' THEN ra.Id END) AS total_answers,
    AVG(ra.Score) AS avg_post_score,
    AVG(ra.ViewCount) AS avg_post_views,
    MIN(ra.CreationDate) AS earliest_post_date,
    MAX(ra.CreationDate) AS latest_post_date,
    COUNT(DISTINCT us.UserId) AS active_users,
    AVG(us.post_count) AS avg_posts_per_user,
    COUNT(DISTINCT CASE WHEN va.vote_category = 'Mod Vote' THEN va.PostId END) AS mod_votes_count,
    COUNT(DISTINCT CASE WHEN va.vote_category = 'Bounty Vote' THEN va.PostId END) AS bounty_votes_count,
    COUNT(DISTINCT ta.TagName) AS total_tags_analyzed,
    AVG(ta.tag_frequency) AS avg_tag_frequency,
    COUNT(DISTINCT CASE WHEN ta.frequency_category = 'High Frequency' THEN ta.TagName END) AS high_freq_tags,
    COUNT(DISTINCT CASE WHEN ta.frequency_category = 'Medium Frequency' THEN ta.TagName END) AS medium_freq_tags,
    AVG(CASE WHEN ra.prev_score IS NOT NULL THEN ra.Score - ra.prev_score ELSE 0 END) AS avg_score_change,
    AVG(CASE WHEN ra.prev_views IS NOT NULL THEN ra.ViewCount - ra.prev_views ELSE 0 END) AS avg_views_change,
    AVG(ra.avg_score_3_posts) AS avg_3post_score_avg,
    AVG(CASE WHEN va.vote_pattern = 'Down-then-Up Vote Pattern' THEN 1 ELSE 0 END) * 100 AS down_then_up_vote_pct,
    AVG(CASE WHEN va.vote_pattern = 'Up-then-Down Vote Pattern' THEN 1 ELSE 0 END) * 100 AS up_then_down_vote_pct,
    MAX(us.reputation_rank) AS max_reputation_rank
FROM RankedPosts ra
LEFT JOIN UserActivityStats us ON ra.OwnerUserId = us.UserId
LEFT JOIN ComplexVotesAnalysis va ON ra.Id = va.PostId
LEFT JOIN PostTags pt ON ra.Id = pt.PostId
LEFT JOIN TagAnalysis ta ON pt.TagName = ta.TagName
WHERE (ra.rn = 1 
   OR ra.post_category = 'Answer'
   OR va.vote_category IS NOT NULL
   OR ta.TagName IS NOT NULL
   OR ra.Score > 0)
GROUP BY
    ra.Id,
    ra.PostTypeId,
    ra.CreationDate,
    ra.Score,
    ra.ViewCount,
    ra.Title,
    ra.Tags,
    ra.OwnerUserId,
    ra.AcceptedAnswerId,
    ra.AnswerCount,
    ra.CommentCount,
    ra.FavoriteCount,
    ra.rn,
    ra.prev_score,
    ra.prev_views,
    ra.avg_score_3_posts,
    ra.max_views_per_user,
    ra.total_posts_per_user,
    ra.post_category,
    ra.title_tag_concat,
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.Views,
    us.UpVotes,
    us.DownVotes,
    us.post_count,
    us.question_count,
    us.answer_count,
    us.total_score,
    us.avg_score,
    us.latest_activity,
    us.all_tags_used,
    us.questions_with_accepted_answers,
    us.posts_with_comments,
    us.reputation_rank,
    va.PostId,
    va.UserId,
    va.VoteTypeId,
    va.CreationDate,
    va.BountyAmount,
    va.vote_category,
    va.vote_rank,
    va.prev_vote_time,
    va.next_vote_type,
    va.vote_pattern,
    va.minutes_since_prev_vote,
    va.minutes_since_prev_vote_by_user,
    ta.TagName,
    ta.tag_frequency,
    ta.ExcerptPostId,
    ta.WikiPostId,
    ta.frequency_category,
    ta.content_status,
    ta.frequency_rank,
    ta.previous_frequency
HAVING COUNT(*) > 0
ORDER BY 
    CASE WHEN AVG(us.post_count) > 10 THEN 1 ELSE 2 END,
    AVG(ta.tag_frequency) DESC,
    COUNT(DISTINCT ra.OwnerUserId) DESC
LIMIT 1000;