-- {"query": "388.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3158}
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
tagged_questions as (
    select p.id,
           p.owneruserid,
           p.creationdate,
           p.score,
           p.viewcount,
           p.title,
           p.tags,
           string_to_array(substring(p.tags, 2, length(p.tags)-2), '><') as tag_arr
    from posts p
    where p.posttypeid = 1
),
answers as (
    select a.id,
           a.parentid as question_id,
           a.owneruserid,
           a.creationdate,
           a.score
    from posts a
    where a.posttypeid = 2
),
q_activity as (
    select q.id as question_id,
           q.owneruserid as asker_id,
           q.creationdate as q_created,
           q.score as q_score,
           q.viewcount as q_views,
           q.title,
           q.tags,
           count(a.id) as answer_count,
           max(a.creationdate) as last_answer_date,
           sum(case when a.score > 0 then 1 else 0 end) as positive_answers,
           sum(case when a.score < 0 then 1 else 0 end) as negative_answers
    from tagged_questions q
    left join answers a on a.question_id = q.id
    group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.title, q.tags
),
votes_agg as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
           sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
           sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
           count(*) as total_votes
    from votes v
    group by v.postid
),
comments_agg as (
    select c.postid,
           count(*) as comment_count,
           max(c.creationdate) as last_comment_date,
           sum(greatest(c.score, 0)) as nonneg_comment_score
    from comments c
    group by c.postid
),
postlinks_norm as (
    select pl.postid,
           pl.relatedpostid,
           pl.linktypeid,
           case when pl.linktypeid = 3 then 1 else 0 end as is_duplicate
    from postlinks pl
),
dup_clusters as (
    select q.id as canonical_id,
           array_agg(distinct pl.postid) filter (where pl.linktypeid = 3 and pl.relatedpostid = q.id) as dup_children
    from posts q
    left join postlinks_norm pl on pl.relatedpostid = q.id and pl.linktypeid = 3
    where q.posttypeid = 1
    group by q.id
),
user_badges as (
    select b.userid,
           sum(case when b.class = 1 then 1 else 0 end) as gold,
           sum(case when b.class = 2 then 1 else 0 end) as silver,
           sum(case when b.class = 3 then 1 else 0 end) as bronze,
           sum(case when b.tagbased = true then 1 else 0 end) as tagbadges,
           count(*) as total_badges,
           min(b.date) as first_badge_date,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
asker_metrics as (
    select u.id as user_id,
           coalesce(sum(case when p.posttypeid = 1 then 1 else 0 end),0) as questions_asked,
           coalesce(sum(case when p.posttypeid = 2 then 1 else 0 end),0) as answers_posted,
           avg(nullif(p.score,0)) as avg_nonzero_post_score,
           sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as total_question_views,
           max(p.lastactivitydate) as last_post_activity
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
post_edits as (
    select ph.postid,
           count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9)) as edit_count,
           max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,7,8,9)) as last_edit_date,
           count(*) filter (where ph.posthistorytypeid in (10,11)) as open_close_events,
           count(*) filter (where ph.posthistorytypeid in (12,13)) as delete_undelete_events
    from posthistory ph
    group by ph.postid
),
question_tag_expansion as (
    select qa.question_id,
           unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag_name
    from q_activity qa
    join posts p on p.id = qa.question_id
    where p.posttypeid = 1 and p.tags is not null and p.tags like '<%>'
),
top_tags as (
    select tag_name,
           count(*) as tag_uses,
           percentile_cont(0.5) within group (order by qa.q_score) as median_score_for_tag
    from question_tag_expansion qte
    join q_activity qa on qa.question_id = qte.question_id
    group by tag_name
),
ranked_questions as (
    select qa.question_id,
           qa.asker_id,
           qa.q_created,
           qa.q_score,
           qa.q_views,
           qa.title,
           qa.tags,
           qa.answer_count,
           qa.last_answer_date,
           qa.positive_answers,
           qa.negative_answers,
           va.upvotes,
           va.downvotes,
           va.favorites,
           va.bounty_started,
           va.bounty_awarded,
           coalesce(va.total_votes,0) as total_votes,
           ca.comment_count,
           ca.last_comment_date,
           coalesce(ca.nonneg_comment_score,0) as comment_positivity,
           pe.edit_count,
           pe.last_edit_date,
           pe.open_close_events,
           pe.delete_undelete_events,
           uc.gold, uc.silver, uc.bronze, uc.tagbadges, uc.total_badges,
           au.reputation as asker_reputation,
           au.creationdate as asker_joined,
           am.questions_asked,
           am.answers_posted,
           am.avg_nonzero_post_score,
           am.total_question_views,
           am.last_post_activity,
           array_length(dc.dup_children,1) as duplicate_children_count
    from q_activity qa
    left join votes_agg va on va.postid = qa.question_id
    left join comments_agg ca on ca.postid = qa.question_id
    left join post_edits pe on pe.postid = qa.question_id
    left join posts q on q.id = qa.question_id
    left join dup_clusters dc on dc.canonical_id = qa.question_id
    left join users au on au.id = qa.asker_id
    left join user_badges uc on uc.userid = qa.asker_id
    left join asker_metrics am on am.user_id = qa.asker_id
),
score_windows as (
    select rq.question_id,
           rq.asker_id,
           rq.q_created,
           rq.q_score,
           rq.q_views,
           rq.title,
           rq.tags,
           rq.answer_count,
           rq.last_answer_date,
           rq.positive_answers,
           rq.negative_answers,
           rq.upvotes,
           rq.downvotes,
           rq.favorites,
           rq.bounty_started,
           rq.bounty_awarded,
           rq.total_votes,
           rq.comment_count,
           rq.last_comment_date,
           rq.comment_positivity,
           rq.edit_count,
           rq.last_edit_date,
           rq.open_close_events,
           rq.delete_undelete_events,
           rq.gold,
           rq.silver,
           rq.bronze,
           rq.tagbadges,
           rq.total_badges,
           rq.asker_reputation,
           rq.asker_joined,
           rq.questions_asked,
           rq.answers_posted,
           rq.avg_nonzero_post_score,
           rq.total_question_views,
           rq.last_post_activity,
           rq.duplicate_children_count,
           row_number() over (order by coalesce(rq.q_score,0) desc, coalesce(rq.q_views,0) desc) as rn_score,
           row_number() over (order by coalesce(rq.total_votes,0) desc, coalesce(rq.comment_count,0) desc) as rn_votes,
           row_number() over (partition by rq.asker_id order by coalesce(rq.q_views,0) desc, coalesce(rq.q_score,0) desc) as rn_by_user,
           rank() over (order by (coalesce(rq.q_score,0) + coalesce(rq.upvotes,0) - coalesce(rq.downvotes,0)) desc) as r_engagement
    from ranked_questions rq
),
recent_hot as (
    select sw.*
    from score_windows sw
    where sw.q_created >= (select max(creationdate) - interval '90 days' from posts)
),
balanced_sample as (
    (
      select sw.*, 'TOP_SCORE' as bucket
      from score_windows sw
      where sw.rn_score <= 200
    )
    union all
    (
      select sw.*, 'TOP_VOTES' as bucket
      from score_windows sw
      where sw.rn_votes <= 200
    )
    union all
    (
      select sw.*, 'PER_USER_TOP' as bucket
      from score_windows sw
      where sw.rn_by_user = 1
    )
    union all
    (
      select rh.*, 'RECENT_HOT' as bucket
      from recent_hot rh
      where rh.r_engagement <= 300
    )
),
bucket_dedup as (
    select bs.*,
           row_number() over (partition by question_id order by
             case bucket when 'TOP_SCORE' then 1 when 'TOP_VOTES' then 2 when 'RECENT_HOT' then 3 else 4 end,
             rn_score, rn_votes
           ) as keep_one
    from balanced_sample bs
),
tag_influence as (
    select bd.question_id,
           avg(tt.median_score_for_tag) as avg_tag_median_score,
           min(tt.tag_uses) as min_tag_popularity,
           max(tt.tag_uses) as max_tag_popularity
    from bucket_dedup bd
    join question_tag_expansion qte on qte.question_id = bd.question_id
    left join top_tags tt on tt.tag_name = qte.tag_name
    where bd.keep_one = 1
    group by bd.question_id
),
normalized as (
    select bd.question_id,
           bd.asker_id,
           bd.q_created,
           bd.q_score,
           bd.q_views,
           bd.title,
           coalesce(nullif(bd.tags, ''), '<untagged>') as tags,
           coalesce(bd.answer_count,0) as answer_count,
           coalesce(bd.upvotes,0) as upvotes,
           coalesce(bd.downvotes,0) as downvotes,
           coalesce(bd.favorites,0) as favorites,
           coalesce(bd.comment_count,0) as comment_count,
           coalesce(bd.comment_positivity,0) as comment_positivity,
           coalesce(bd.edit_count,0) as edit_count,
           extract(epoch from (timestamp '2024-10-01 12:34:56' - bd.q_created)) / 86400.0 as age_days,
           case when bd.duplicate_children_count is null then 0 else bd.duplicate_children_count end as dup_children,
           case when bd.last_edit_date is null then 0 else extract(epoch from (timestamp '2024-10-01 12:34:56' - bd.last_edit_date)) / 86400.0 end as days_since_edit,
           case when bd.last_comment_date is null then 0 else extract(epoch from (timestamp '2024-10-01 12:34:56' - bd.last_comment_date)) / 86400.0 end as days_since_comment,
           bd.asker_reputation,
           coalesce(bd.total_badges,0) as asker_badges,
           coalesce(bd.gold,0) as asker_gold,
           coalesce(bd.silver,0) as asker_silver,
           coalesce(bd.bronze,0) as asker_bronze
    from bucket_dedup bd
    where bd.keep_one = 1
)
select
    n.question_id,
    n.title,
    n.tags,
    n.q_score,
    n.q_views,
    n.answer_count,
    n.upvotes,
    n.downvotes,
    n.favorites,
    n.comment_count,
    n.comment_positivity,
    n.edit_count,
    n.age_days,
    n.days_since_edit,
    n.days_since_comment,
    n.dup_children,
    n.asker_id,
    n.asker_reputation,
    n.asker_badges,
    n.asker_gold,
    n.asker_silver,
    n.asker_bronze,
    ti.avg_tag_median_score,
    ti.min_tag_popularity,
    ti.max_tag_popularity,
    (
      0.40 * ln(1 + greatest(n.q_views,0)) +
      0.35 * (coalesce(n.upvotes,0) - 0.8 * coalesce(n.downvotes,0)) +
      0.15 * (least(10, n.answer_count)) +
      0.10 * (coalesce(n.comment_positivity,0) / nullif(n.comment_count,0)) +
      0.05 * (coalesce(n.favorites,0)) -
      0.07 * ln(1 + n.age_days) -
      0.06 * ln(1 + n.days_since_edit) -
      0.03 * n.dup_children +
      0.02 * coalesce(ti.avg_tag_median_score, 0)
    ) as perf_score,
    upper(trim(regexp_replace(coalesce(n.title,''), '\s+', ' ', 'g'))) as title_norm,
    case
      when n.q_score >= 50 and n.q_views >= 10000 then 'VIRAL'
      when n.q_score >= 20 and n.q_views >= 3000 then 'HOT'
      when n.q_score >= 5 and n.q_views >= 1000 then 'WARM'
      when n.q_score is null or n.q_views is null then 'UNKNOWN'
      else 'COLD'
    end as heat_bucket
from normalized n
left join tag_influence ti on ti.question_id = n.question_id
where
    (n.upvotes - n.downvotes) >= -2
    and (
        n.answer_count >= 0
        or (n.comment_count > 0 and n.edit_count >= 0)
    )
    and (
        n.tags like '%<sql>%'
        or n.tags like '%<postgresql>%'
        or n.tags like '%<performance>%'
        or position('<database>' in n.tags) > 0
    )
    and coalesce(n.q_views,0) >= 0
order by perf_score desc nulls last, n.q_score desc nulls last, n.q_views desc nulls last
limit 500;