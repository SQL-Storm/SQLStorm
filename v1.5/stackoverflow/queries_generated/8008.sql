-- {"query": "8008.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3706} 
with
recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    u.websiteurl,
    coalesce(nullif(trim(u.aboutme), ''), '[no about]') as about_normalized,
    u.upvotes,
    u.downvotes,
    u.views
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
question_posts as (
  select
    p.id,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.answercount,
    p.favoritecount,
    p.closeddate,
    p.communityowneddate,
    p.acceptedanswerid
  from posts p
  where p.posttypeid = 1
),
answer_posts as (
  select
    a.id,
    a.parentid as question_id,
    a.owneruserid,
    a.creationdate,
    a.score,
    a.commentcount
  from posts a
  where a.posttypeid = 2
),
tag_expanded as (
  select
    q.id as question_id,
    unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
  from question_posts q
  where q.tags is not null and length(q.tags) > 2
),
user_activity as (
  select
    ru.user_id,
    count(distinct q.id) filter (where q.id is not null) as questions_asked,
    count(distinct a.id) filter (where a.id is not null) as answers_posted,
    sum(greatest(q.score,0)) filter (where q.id is not null) as question_pos_score,
    sum(greatest(a.score,0)) filter (where a.id is not null) as answer_pos_score,
    sum(least(q.score,0)) filter (where q.id is not null) as question_neg_score,
    sum(least(a.score,0)) filter (where a.id is not null) as answer_neg_score,
    max(q.creationdate) as last_question_date,
    max(a.creationdate) as last_answer_date
  from recent_users ru
  left join question_posts q on q.owneruserid = ru.user_id
  left join answer_posts a on a.owneruserid = ru.user_id
  group by ru.user_id
),
user_badges as (
  select
    b.userid as user_id,
    count(*) as total_badges,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    count(*) filter (where b.tagbased = 1) as tag_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
q_quality as (
  select
    q.id as question_id,
    q.owneruserid as user_id,
    q.score,
    q.viewcount,
    q.answercount,
    q.favoritecount,
    q.acceptedanswerid,
    case when q.closeddate is not null then 1 else 0 end as is_closed,
    case when q.communityowneddate is not null then 1 else 0 end as is_community,
    count(distinct c.id) as comment_count,
    count(distinct v.id) filter (where v.votetypeid = 2) as upvotes,
    count(distinct v.id) filter (where v.votetypeid = 3) as downvotes,
    count(distinct v.id) filter (where v.votetypeid = 5) as favorites_votes,
    percentile_cont(0.5) within group (order by a.score) as median_answer_score,
    avg(a.score) as avg_answer_score
  from question_posts q
  left join comments c on c.postid = q.id
  left join votes v on v.postid = q.id
  left join answer_posts a on a.question_id = q.id
  group by q.id, q.owneruserid, q.score, q.viewcount, q.answercount, q.favoritecount, q.acceptedanswerid, q.closeddate, q.communityowneddate
),
tag_stats as (
  select
    t.tagname,
    count(distinct te.question_id) as questions_with_tag,
    avg(q.score) as avg_q_score,
    avg(q.viewcount) as avg_q_views,
    sum(case when q.acceptedanswerid is not null then 1 else 0 end) as solved_count
  from tag_expanded te
  join q_quality q on q.question_id = te.question_id
  join tags t on lower(t.tagname) = lower(te.tagname)
  group by t.tagname
),
recent_hot as (
  select
    q.question_id,
    q.user_id,
    q.score,
    q.viewcount,
    q.answercount,
    q.upvotes,
    q.downvotes,
    q.comment_count,
    (q.upvotes - q.downvotes) as net_votes,
    coalesce(nullif(trim(q_quality.title), ''), '[untitled]') as norm_title
  from q_quality q
  join posts q_quality on q_quality.id = q.question_id
  where q.viewcount > (select percentile_cont(0.9) within group (order by viewcount) from question_posts)
),
user_engagement as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.creationdate,
    ua.questions_asked,
    ua.answers_posted,
    ua.question_pos_score + ua.answer_pos_score as positive_scores,
    ua.question_neg_score + ua.answer_neg_score as negative_scores,
    coalesce(ub.total_badges, 0) as total_badges,
    coalesce(ub.gold_badges, 0) as gold_badges,
    coalesce(ub.silver_badges, 0) as silver_badges,
    coalesce(ub.bronze_badges, 0) as bronze_badges,
    coalesce(ub.tag_badges, 0) as tag_badges,
    greatest(coalesce(ua.last_question_date, timestamp 'epoch'), coalesce(ua.last_answer_date, timestamp 'epoch')) as last_post_date,
    ru.location,
    ru.websiteurl,
    ru.views,
    ru.upvotes,
    ru.downvotes
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join user_badges ub on ub.user_id = ru.user_id
),
user_ranked as (
  select
    ue.*,
    row_number() over (order by coalesce(questions_asked,0) + coalesce(answers_posted,0) desc, coalesce(positive_scores,0) - abs(coalesce(negative_scores,0)) desc, reputation desc) as activity_rank,
    ntile(10) over (order by coalesce(questions_asked,0) + coalesce(answers_posted,0) desc) as decile_activity,
    ntile(10) over (order by reputation desc) as decile_rep
  from user_engagement ue
),
dupe_links as (
  select
    pl.postid as duplicate_id,
    pl.relatedpostid as original_id,
    count(*) as dupe_edges
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid, pl.relatedpostid
),
close_events as (
  select
    ph.postid,
    min(ph.creationdate) as first_closed_at,
    max(ph.creationdate) as last_closed_at,
    count(*) as close_events,
    count(*) filter (where ph.comment ~ '\"OriginalQuestionIds\"') as dupe_votes_with_targets
  from posthistory ph
  where ph.posthistorytypeid = 10
  group by ph.postid
),
question_enriched as (
  select
    q.question_id,
    q.user_id,
    q.score,
    q.viewcount,
    q.answercount,
    q.favoritecount,
    q.acceptedanswerid,
    q.is_closed,
    q.is_community,
    q.comment_count,
    q.upvotes,
    q.downvotes,
    q.favorites_votes,
    q.median_answer_score,
    q.avg_answer_score,
    coalesce(ce.close_events, 0) as close_events,
    ce.first_closed_at,
    ce.last_closed_at,
    coalesce(dl.dupe_edges, 0) as dupe_edges
  from q_quality q
  left join close_events ce on ce.postid = q.question_id
  left join dupe_links dl on dl.duplicate_id = q.question_id
),
user_q_agg as (
  select
    qe.user_id,
    count(*) as total_questions,
    sum(case when qe.acceptedanswerid is not null then 1 else 0 end) as solved_questions,
    avg(qe.score) as avg_q_score,
    avg(qe.viewcount) as avg_q_views,
    percentile_cont(0.5) within group (order by qe.viewcount) as median_q_views,
    sum(qe.close_events) as total_close_events,
    sum(qe.dupe_edges) as total_dupe_edges
  from question_enriched qe
  group by qe.user_id
),
user_a_agg as (
  select
    a.owneruserid as user_id,
    count(*) as total_answers,
    avg(a.score) as avg_a_score,
    percentile_cont(0.5) within group (order by a.score) as median_a_score,
    sum(case when a.score > 0 then 1 else 0 end) as positive_answers
  from answer_posts a
  group by a.owneruserid
),
user_comment_agg as (
  select
    coalesce(c.userid, p.owneruserid) as user_id,
    count(*) as comments_authored,
    sum(case when c.score > 0 then 1 else 0 end) as positive_comments,
    avg(c.score) as avg_comment_score
  from comments c
  left join posts p on p.id = c.postid
  group by coalesce(c.userid, p.owneruserid)
),
final_users as (
  select
    ur.user_id,
    ur.displayname,
    ur.reputation,
    ur.creationdate,
    ur.location,
    ur.websiteurl,
    ur.views,
    ur.upvotes,
    ur.downvotes,
    ur.activity_rank,
    ur.decile_activity,
    ur.decile_rep,
    coalesce(uq.total_questions, 0) as total_questions,
    coalesce(uq.solved_questions, 0) as solved_questions,
    coalesce(ua.total_answers, 0) as total_answers,
    coalesce(ua.positive_answers, 0) as positive_answers,
    coalesce(uc.comments_authored, 0) as comments_authored,
    coalesce(uc.positive_comments, 0) as positive_comments,
    coalesce(uq.avg_q_score, 0) as avg_q_score,
    coalesce(ua.avg_a_score, 0) as avg_a_score,
    coalesce(uq.avg_q_views, 0) as avg_q_views,
    coalesce(uq.median_q_views, 0) as median_q_views,
    coalesce(ua.median_a_score, 0) as median_a_score,
    coalesce(uq.total_close_events, 0) as total_close_events,
    coalesce(uq.total_dupe_edges, 0) as total_dupe_edges
  from user_ranked ur
  left join user_q_agg uq on uq.user_id = ur.user_id
  left join user_a_agg ua on ua.user_id = ur.user_id
  left join user_comment_agg uc on uc.user_id = ur.user_id
),
title_similarity as (
  select
    q1.id as qid1,
    q2.id as qid2,
    q1.owneruserid as user1,
    q2.owneruserid as user2,
    avg(similarity(lower(q1.title), lower(q2.title))) over () as global_title_sim_avg,
    similarity(lower(q1.title), lower(q2.title)) as pair_title_sim
  from posts q1
  join posts q2 on q1.id < q2.id
  where q1.posttypeid = 1 and q2.posttypeid = 1
    and q1.creationdate >= now() - interval '180 days'
    and q2.creationdate >= now() - interval '180 days'
    and q1.title is not null and q2.title is not null
    and length(q1.title) > 10 and length(q2.title) > 10
    and similarity(lower(q1.title), lower(q2.title)) > 0.4
),
user_title_overlap as (
  select
    user1 as user_id,
    count(*) as similar_title_pairs_authored
  from title_similarity
  group by user1
),
heavy_tag_users as (
  select
    te.tagname,
    q.owneruserid as user_id,
    count(*) as tag_questions,
    rank() over (partition by te.tagname order by count(*) desc) as rnk
  from tag_expanded te
  join question_posts q on q.id = te.question_id
  group by te.tagname, q.owneruserid
),
tag_top_authors as (
  select
    htu.tagname,
    htu.user_id,
    htu.tag_questions
  from heavy_tag_users htu
  where htu.rnk <= 3
),
recent_dupe_ratio as (
  select
    q.user_id,
    sum(case when q.dupe_edges > 0 then 1 else 0 end)::float / nullif(count(*),0) as dupe_ratio_recent
  from question_enriched q
  join posts p on p.id = q.question_id
  where p.creationdate >= now() - interval '90 days'
  group by q.user_id
)
select
  fu.user_id,
  fu.displayname,
  fu.reputation,
  fu.activity_rank,
  fu.decile_activity,
  fu.decile_rep,
  fu.total_questions,
  fu.solved_questions,
  fu.total_answers,
  fu.positive_answers,
  fu.comments_authored,
  fu.positive_comments,
  fu.avg_q_score,
  fu.avg_a_score,
  fu.avg_q_views,
  fu.median_q_views,
  fu.median_a_score,
  fu.total_close_events,
  fu.total_dupe_edges,
  coalesce(rdr.dupe_ratio_recent, 0.0) as dupe_ratio_recent,
  coalesce(uto.similar_title_pairs_authored, 0) as similar_title_pairs_authored,
  array_agg(distinct concat(tt.tagname, ':', tt.tag_questions) order by tt.tag_questions desc) filter (where tt.tagname is not null) as top_tags,
  (
    select count(*) from recent_hot rh where rh.user_id = fu.user_id
  ) as recent_hot_questions,
  (
    select string_agg(distinct t.tagname, ', ' order by t.tagname)
    from tag_top_authors t
    where t.user_id = fu.user_id
  ) as champion_tags,
  case
    when fu.reputation >= 100000 then 'legend'
    when fu.reputation >= 50000 then 'elite'
    when fu.reputation >= 10000 then 'advanced'
    when fu.reputation >= 1000 then 'intermediate'
    else 'novice'
  end as cohort,
  greatest(coalesce(fu.total_answers,0), 1) as safe_div_total_answers,
  coalesce(round(100.0 * fu.solved_questions / nullif(fu.total_questions,0), 2), 0.0) as q_solve_rate_pct,
  coalesce(round(100.0 * fu.positive_answers / nullif(fu.total_answers,0), 2), 0.0) as positive_answer_rate_pct
from final_users fu
left join user_title_overlap uto on uto.user_id = fu.user_id
left join tag_top_authors tt on tt.user_id = fu.user_id
left join recent_dupe_ratio rdr on rdr.user_id = fu.user_id
where
  (
    fu.reputation > (select avg(reputation) from users)
    or fu.total_answers >= (select percentile_cont(0.9) within group (order by total_answers) from user_a_agg)
    or fu.total_questions >= (select percentile_cont(0.9) within group (order by total_questions) from user_q_agg)
  )
  and coalesce(fu.displayname, '') not ilike '%bot%'
group by
  fu.user_id, fu.displayname, fu.reputation, fu.activity_rank, fu.decile_activity, fu.decile_rep,
  fu.total_questions, fu.solved_questions, fu.total_answers, fu.positive_answers,
  fu.comments_authored, fu.positive_comments, fu.avg_q_score, fu.avg_a_score,
  fu.avg_q_views, fu.median_q_views, fu.median_a_score, fu.total_close_events, fu.total_dupe_edges,
  rdr.dupe_ratio_recent, uto.similar_title_pairs_authored
order by
  fu.activity_rank,
  fu.reputation desc
limit 500;