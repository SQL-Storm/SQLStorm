-- {"query": "673.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2628} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    row_number() over (order by u.creationdate desc, u.id desc) as rn
  from users u
  where u.creationdate > now() - interval '5 years'
),
active_questions as (
  select
    p.id as question_id,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.acceptedanswerid,
    p.closeddate,
    coalesce(p.answercount, 0) as answercount
  from posts p
  where p.posttypeid = 1
),
answers as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as answer_owner_id,
    a.score as answer_score,
    a.creationdate as answer_date
  from posts a
  where a.posttypeid = 2
),
question_stats as (
  select
    q.question_id,
    q.owneruserid,
    q.creationdate,
    q.score,
    q.viewcount,
    q.title,
    q.tags,
    q.acceptedanswerid,
    q.closeddate,
    q.answercount,
    count(ans.answer_id) as total_answers,
    sum(case when ans.answer_score > 0 then 1 else 0 end) as positive_answers,
    max(ans.answer_score) as max_answer_score,
    min(ans.answer_score) as min_answer_score,
    avg(ans.answer_score) as avg_answer_score
  from active_questions q
  left join answers ans on ans.question_id = q.question_id
  group by
    q.question_id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.title, q.tags, q.acceptedanswerid, q.closeddate, q.answercount
),
votes_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_start,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_close,
    min(v.creationdate) as first_vote_at,
    max(v.creationdate) as last_vote_at
  from votes v
  group by v.postid
),
comment_activity as (
  select
    c.postid,
    count(*) as comment_count,
    sum(case when c.score > 0 then 1 else 0 end) as positive_comments,
    max(c.creationdate) as last_comment_at
  from comments c
  group by c.postid
),
tag_expansion as (
  select
    q.question_id,
    unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
  from active_questions q
  where q.tags is not null and length(q.tags) >= 2
),
tag_rank as (
  select
    te.question_id,
    te.tag,
    t.count as tag_global_count,
    dense_rank() over (partition by te.question_id order by t.count desc nulls last, lower(te.tag)) as tag_pop_rank
  from tag_expansion te
  left join tags t on lower(t.tagname) = lower(te.tag)
),
dup_links as (
  select pl.postid as question_id,
         count(*) filter (where pl.linktypeid = 3) as dup_count,
         bool_or(pl.linktypeid = 3) as has_dup
  from postlinks pl
  group by pl.postid
),
history_flags as (
  select
    ph.postid as question_id,
    max(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as was_closed_or_migrated,
    max(case when ph.posthistorytypeid = 11 then 1 else 0 end) as was_reopened,
    max(case when ph.posthistorytypeid in (12,10) then 1 else 0 end) as had_moderation,
    max(case when ph.posthistorytypeid in (24) then 1 else 0 end) as had_suggested_edit,
    max(case when ph.posthistorytypeid in (52) then 1 else 0 end) as was_hot
  from posthistory ph
  group by ph.postid
),
owner_profile as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    u.websiteurl,
    u.views as profile_views,
    u.upvotes as total_upvotes_cast,
    u.downvotes as total_downvotes_cast,
    ntile(5) over (order by u.reputation desc, u.id) as rep_quintile
  from users u
),
accepted_answer_latency as (
  select
    q.question_id,
    case
      when q.acceptedanswerid is null then null
      else (
        select a.creationdate - q.creationdate
        from posts a
        where a.id = q.acceptedanswerid and a.posttypeid = 2
      )
    end as time_to_accept
  from active_questions q
),
badge_summary as (
  select
    b.userid,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    count(*) as total_badges,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
question_quality as (
  select
    qs.question_id,
    qs.owneruserid,
    qs.creationdate,
    qs.score,
    qs.viewcount,
    qs.title,
    qs.tags,
    qs.answercount,
    coalesce(va.upvotes,0) as upvotes,
    coalesce(va.downvotes,0) as downvotes,
    coalesce(ca.comment_count,0) as comment_count,
    coalesce(ca.positive_comments,0) as positive_comments,
    coalesce(va.bounty_start,0) as bounty_start,
    coalesce(va.bounty_close,0) as bounty_close,
    va.first_vote_at,
    va.last_vote_at,
    coalesce(dl.dup_count,0) as dup_count,
    coalesce(hf.was_closed_or_migrated,0) as was_closed_or_migrated,
    coalesce(hf.was_reopened,0) as was_reopened,
    coalesce(hf.had_moderation,0) as had_moderation,
    coalesce(hf.had_suggested_edit,0) as had_suggested_edit,
    coalesce(hf.was_hot,0) as was_hot
  from question_stats qs
  left join votes_agg va on va.postid = qs.question_id
  left join comment_activity ca on ca.postid = qs.question_id
  left join dup_links dl on dl.question_id = qs.question_id
  left join history_flags hf on hf.question_id = qs.question_id
),
scored_questions as (
  select
    qq.*,
    aa.time_to_accept,
    case
      when qq.viewcount is null or qq.viewcount = 0 then null
      else round((qq.upvotes - qq.downvotes)::numeric / greatest(1, qq.viewcount) * 1000, 3)
    end as votes_per_kview,
    case
      when qq.answercount = 0 then null
      else round(qq.upvotes::numeric / qq.answercount, 3)
    end as upvotes_per_answer,
    case
      when qq.comment_count = 0 then null
      else round(qq.positive_comments::numeric / qq.comment_count, 3)
    end as positive_comment_ratio,
    case
      when qq.was_closed_or_migrated = 1 then 'ClosedOrMigrated'
      when qq.was_hot = 1 then 'Hot'
      when qq.dup_count > 0 then 'Duplicate'
      when qq.was_reopened = 1 then 'Reopened'
      else 'Normal'
    end as moderation_status
  from question_quality qq
  left join accepted_answer_latency aa on aa.question_id = qq.question_id
),
tag_pivot as (
  select
    tr.question_id,
    max(case when tr.tag_pop_rank = 1 then tr.tag end) as top_tag,
    max(case when tr.tag_pop_rank = 2 then tr.tag end) as second_tag
  from tag_rank tr
  where tr.tag_pop_rank <= 2
  group by tr.question_id
),
owner_enriched as (
  select
    op.user_id,
    op.displayname,
    op.reputation,
    op.rep_quintile,
    coalesce(bs.total_badges,0) as total_badges,
    coalesce(bs.gold_badges,0) as gold_badges,
    coalesce(bs.silver_badges,0) as silver_badges,
    coalesce(bs.bronze_badges,0) as bronze_badges,
    bs.last_badge_at
  from owner_profile op
  left join badge_summary bs on bs.userid = op.user_id
),
ranked_output as (
  select
    sq.question_id,
    sq.owneruserid,
    oe.displayname as owner_name,
    oe.reputation as owner_rep,
    oe.rep_quintile,
    oe.total_badges,
    oe.gold_badges,
    oe.silver_badges,
    oe.bronze_badges,
    sq.creationdate,
    sq.title,
    coalesce(tp.top_tag, '[untagged]') as top_tag,
    coalesce(tp.second_tag, null) as second_tag,
    sq.score,
    sq.upvotes,
    sq.downvotes,
    sq.viewcount,
    sq.answercount,
    sq.comment_count,
    sq.votes_per_kview,
    sq.upvotes_per_answer,
    sq.positive_comment_ratio,
    sq.time_to_accept,
    sq.moderation_status,
    sq.was_hot,
    sq.had_suggested_edit,
    sq.had_moderation,
    sq.dup_count,
    row_number() over (
      partition by oe.rep_quintile
      order by
        coalesce(sq.votes_per_kview, -1) desc,
        coalesce(sq.upvotes_per_answer, -1) desc,
        sq.viewcount desc,
        sq.score desc,
        sq.creationdate desc,
        sq.question_id desc
    ) as rn_in_quintile
  from scored_questions sq
  left join tag_pivot tp on tp.question_id = sq.question_id
  left join owner_enriched oe on oe.user_id = sq.owneruserid
  where
    (sq.creationdate > now() - interval '5 years' or sq.was_hot = 1)
    and coalesce(sq.upvotes,0) + coalesce(sq.downvotes,0) > 0
)
select
  ro.rep_quintile,
  ro.rn_in_quintile,
  ro.question_id,
  ro.owneruserid as owner_id,
  ro.owner_name,
  ro.owner_rep,
  ro.total_badges,
  ro.gold_badges,
  ro.silver_badges,
  ro.bronze_badges,
  ro.creationdate,
  ro.title,
  ro.top_tag,
  ro.second_tag,
  ro.score,
  ro.upvotes,
  ro.downvotes,
  ro.viewcount,
  ro.answercount,
  ro.comment_count,
  ro.votes_per_kview,
  ro.upvotes_per_answer,
  ro.positive_comment_ratio,
  ro.time_to_accept,
  ro.moderation_status,
  ro.was_hot,
  ro.had_suggested_edit,
  ro.had_moderation,
  ro.dup_count
from ranked_output ro
where ro.rn_in_quintile <= 50
order by ro.rep_quintile, ro.rn_in_quintile;