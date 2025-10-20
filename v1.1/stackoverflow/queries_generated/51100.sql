-- {"query": "51100.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 1490} 

WITH user_engagement AS (
    SELECT 
        u.id AS user_id,
        u.reputation,
        u.upvotes,
        u.downvotes,
        COUNT(DISTINCT p.id) AS post_count,
        SUM(CASE WHEN p.posttypeid = 1 THEN 1 ELSE 0 END) AS question_count,
        SUM(CASE WHEN p.posttypeid = 2 THEN 1 ELSE 0 END) AS answer_count,
        AVG(p.score) AS avg_post_score,
        SUM(p.viewcount) AS total_views,
        COUNT(DISTINCT CASE WHEN v.votetypeid = 2 THEN v.postid END) AS upvotes_received,
        COUNT(DISTINCT CASE WHEN v.votetypeid = 3 THEN v.postid END) AS downvotes_received
    FROM users u
    LEFT JOIN posts p ON p.owneruserid = u.id AND p.owneruserid > 0
    LEFT JOIN votes v ON v.postid = p.id 
    WHERE u.creationdate > NOW() - INTERVAL '5 years'
    GROUP BY u.id, u.reputation, u.upvotes, u.downvotes
),
question_complexity AS (
    SELECT 
        p.id AS question_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.commentcount,
        p.favoritecount,
        LENGTH(p.body) AS body_length,
        LENGTH(p.tags) AS tags_length,
        COUNT(DISTINCT ph.id) AS revision_count,
        COUNT(DISTINCT pl.relatedpostid) AS link_count,
        ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.tags FROM 2 FOR LENGTH(p.tags)-2), '><'), 1) AS tag_diversity,
        AVG(c.score) AS avg_comment_score,
        MAX(p.lastactivitydate) AS last_activity
    FROM posts p
    LEFT JOIN posthistory ph ON ph.postid = p.id AND ph.posthistorytypeid IN (1,2,3,4,5,6,7,8,9)
    LEFT JOIN postlinks pl ON pl.postid = p.id AND pl.linktypeid = 1
    LEFT JOIN comments c ON c.postid = p.id
    WHERE p.posttypeid = 1 
      AND p.creationdate > NOW() - INTERVAL '3 years'
      AND p.deleteddate IS NULL
    GROUP BY p.id, p.creationdate, p.score, p.viewcount, p.answercount, p.commentcount, 
             p.favoritecount, p.body, p.tags, p.lastactivitydate
),
answer_quality AS (
    SELECT 
        p.id AS answer_id,
        p.posttypeid,
        p.score,
        p.creationdate,
        p.owneruserid,
        p.parentid,
        LENGTH(p.body) AS answer_length,
        COUNT(DISTINCT c.id) AS comment_count_on_answer,
        AVG(v.bountyamount) AS avg_bounty_received,
        CASE WHEN parent.acceptedanswerid = p.id THEN 1 ELSE 0 END AS is_accepted
    FROM posts p
    JOIN posts parent ON p.parentid = parent.id
    LEFT JOIN comments c ON c.postid = p.id
    LEFT JOIN votes v ON v.postid = p.id AND v.votetypeid = 8
    WHERE p.posttypeid = 2 
      AND p.creationdate > NOW() - INTERVAL '2 years'
      AND parent.creationdate > NOW() - INTERVAL '3 years'
    GROUP BY p.id, p.posttypeid, p.score, p.creationdate, p.owneruserid, p.parentid, 
             p.body, parent.acceptedanswerid
),
badge_patterns AS (
    SELECT 
        b.userid,
        b.class,
        COUNT(*) AS badge_count,
        COUNT(CASE WHEN b.tagbased = 1 THEN 1 END) AS tag_badges,
        COUNT(CASE WHEN b.name LIKE '%Gold%' OR b.class = 1 THEN 1 END) AS gold_badges,
        MIN(b.date) AS first_badge_date,
        MAX(b.date) AS last_badge_date,
        AVG(EXTRACT(EPOCH FROM (b.date - u.creationdate))/86400) AS days_to_badge
    FROM badges b
    JOIN users u ON b.userid = u.id
    WHERE b.date > NOW() - INTERVAL '4 years'
    GROUP BY b.userid, b.class
),
tag_popularity AS (
    SELECT 
        t.tagname,
        t.count AS usage_count,
        p.score AS avg_question_score,
        AVG(p.viewcount) AS avg_views,
        COUNT(DISTINCT p.id) AS total_questions,
        SUM(p.answercount) AS total_answers,
        AVG(LENGTH(p.body)) AS avg_body_length
    FROM tags t
    JOIN posts p ON position(t.tagname IN p.tags) > 0
    WHERE t.count > 100
      AND p.posttypeid = 1
      AND p.creationdate > NOW() - INTERVAL '18 months'
    GROUP BY t.tagname, t.count, p.score
    HAVING COUNT(DISTINCT p.id) > 50
)
SELECT 
    ue.user_id,
    ue.reputation,
    ue.post_count,
    ue.question_count,
    ue.answer_count,
    ue.avg_post_score,
    qc.question_id,
    qc.score AS question_score,
    qc.viewcount,
    qc.answercount,
    qc.tag_diversity,
    qc.revision_count,
    aq.answer_id,
    aq.answer_score,
    aq.is_accepted,
    bp.badge_count,
    bp.gold_badges,
    tp.tagname AS popular_tag,
    tp.avg_views AS tag_avg_views,
    ROW_NUMBER() OVER (
        PARTITION BY ue.user_id 
        ORDER BY qc.score DESC, aq.answer_score DESC
    ) AS ranking,
    PERCENT_RANK() OVER (
        ORDER BY ue.reputation + COALESCE(bp.gold_badges, 0) * 1000
    ) AS reputation_percentile
FROM user_engagement ue
LEFT JOIN question_complexity qc ON qc.owneruserid = ue.user_id 
    AND qc.creationdate BETWEEN ue.creationdate AND ue.creationdate + INTERVAL '1 year'
LEFT JOIN answer_quality aq ON aq.owneruserid = ue.user_id 
    AND aq.creationdate BETWEEN ue.creationdate AND ue.creationdate + INTERVAL '2 years'
LEFT JOIN badge_patterns bp ON bp.userid = ue.user_id
LEFT JOIN (
    SELECT DISTINCT ON (p.owneruserid) 
        p.owneruserid, 
        t.tagname,
        t.avg_views
    FROM posts p
    JOIN tag_popularity t ON position(t.tagname IN p.tags) > 0
    WHERE p.posttypeid = 1
    ORDER BY p.owneruserid, t.avg_views DESC
) tp ON tp.owneruserid = ue.user_id
WHERE ue.reputation > 1000
  AND ue.post_count > 10
  AND (qc.answercount > 2 OR aq.answer_count > 5)
ORDER BY ue.reputation DESC, qc.viewcount DESC, bp.gold_badges DESC
LIMIT 1000;
