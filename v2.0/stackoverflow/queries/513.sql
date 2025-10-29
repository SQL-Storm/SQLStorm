-- {"query": "513.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2991}
with recent_activity as (
  select
    p.id as post_id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.answercount,
    p.favoritecount,
    p.closeddate,
    p.lastactivitydate,
    coalesce(p.lasteditdate, p.creationdate) as last_edit_or_create,
    ph_types.name as last_history_event,
    ph.posthistorytypeid,
    ph.creationdate as last_history_date,
    row_number() over (partition by p.id order by ph.creationdate desc) as rn_hist
  from posts p
  left join lateral (
    select ph1.*
    from posthistory ph1
    where ph1.postid = p.id
    order by ph1.creationdate desc
    limit 1
  ) ph on true
  left join posthistorytypes ph_types on ph_types.id = ph.posthistorytypeid
  where p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
),
user_rollup as (
  select
    u.id as user_id,
    u.reputation,
    u.creationdate as user_created,
    u.displayname,
    u.location,
    u.upvotes,
    u.downvotes,
    u.views as profile_views,
    coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown.host') as website_host,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    count(b.id) as total_badges,
    max(b.date) as last_badge_date
  from users u
  left join badges b on b.userid = u.id
  group by u.id, u.reputation, u.creationdate, u.displayname, u.location, u.upvotes, u.downvotes, u.views, u.websiteurl
),
question_core as (
  select
    ra.post_id,
    ra.owneruserid,
    ra.title,
    ra.tags,
    ra.score,
    ra.viewcount,
    ra.answercount,
    ra.favoritecount,
    ra.creationdate,
    ra.lastactivitydate,
    ra.closeddate,
    ra.last_edit_or_create,
    ra.last_history_event,
    ra.last_history_date
  from recent_activity ra
  where ra.posttypeid = 1
),
answers_core as (
  select
    p.parentid as question_id,
    count(*) as answers_total,
    sum(case when p.score > 0 then 1 else 0 end) as answers_positive,
    sum(case when p.score < 0 then 1 else 0 end) as answers_negative,
    max(p.score) as max_answer_score,
    min(p.score) filter (where p.score is not null) as min_answer_score,
    max(p.creationdate) as last_answer_date
  from posts p
  where p.posttypeid = 2
    and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
  group by p.parentid
),
votes_agg as (
  select
    v.postid,
    count(*) filter (where v.votetypeid = 2) as upvotes_count,
    count(*) filter (where v.votetypeid = 3) as downvotes_count,
    count(*) filter (where v.votetypeid = 5) as favorites_count,
    count(*) filter (where v.votetypeid in (8,9)) as bounty_events,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_amount_total,
    min(v.creationdate) as first_vote_date,
    max(v.creationdate) as last_vote_date
  from votes v
  join posts p on p.id = v.postid
  where p.posttypeid = 1
    and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
  group by v.postid
),
comments_agg as (
  select
    c.postid,
    count(*) as comment_count,
    max(c.creationdate) as last_comment_date,
    sum(greatest(c.score, 0)) as comment_karma_nonneg,
    sum(case when c.userid is null then 1 else 0 end) as anon_comments
  from comments c
  join posts p on p.id = c.postid
  where p.posttypeid = 1
    and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
  group by c.postid
),
links_agg as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 1) as linked_out_count,
    count(*) filter (where pl.linktypeid = 3) as duplicate_of_count,
    max(case when pl.linktypeid = 3 then pl.relatedpostid end) as any_duplicate_target
  from postlinks pl
  group by pl.postid
),
tag_explode as (
  select
    qc.post_id,
    unnest(string_to_array(substring(coalesce(qc.tags, ''), 2, greatest(length(coalesce(qc.tags, ''))-2,0)), '><')) as tagname
  from question_core qc
),
tag_rank as (
  select
    te.post_id,
    te.tagname,
    t.count as global_tag_popularity,
    row_number() over (partition by te.post_id order by coalesce(t.count,0) desc, te.tagname) as tag_rank_by_pop
  from tag_explode te
  left join tags t on lower(t.tagname) = lower(te.tagname)
),
top2_tags as (
  select post_id,
         string_agg(tagname, ', ' order by tag_rank_by_pop) as top_two_tags
  from tag_rank
  where tag_rank_by_pop <= 2
  group by post_id
),
owner_enriched as (
  select
    qc.post_id,
    ur.user_id,
    ur.displayname,
    ur.location,
    ur.reputation,
    ur.upvotes,
    ur.downvotes,
    ur.profile_views,
    ur.website_host,
    ur.total_badges,
    ur.gold_badges,
    ur.silver_badges,
    ur.bronze_badges,
    cast(floor(date_part('day', age(cast('2024-10-01 12:34:56' as timestamp), ur.user_created)) / 365.25) as integer) as account_age_years,
    case
      when ur.reputation >= 100000 then 'legend'
      when ur.reputation >= 20000 then 'veteran'
      when ur.reputation >= 3000 then 'experienced'
      when ur.reputation >= 300 then 'intermediate'
      else 'newbie'
    end as rep_bucket
  from question_core qc
  left join user_rollup ur on ur.user_id = qc.owneruserid
),
activity_windows as (
  select
    qc.post_id,
    qc.creationdate,
    qc.lastactivitydate,
    qc.last_edit_or_create,
    extract(epoch from (qc.lastactivitydate - qc.creationdate)) / 3600.0 as lifetime_hours,
    extract(epoch from (coalesce(qc.last_history_date, qc.lastactivitydate) - qc.creationdate)) / 3600.0 as last_event_after_hours
  from question_core qc
),
quality_scores as (
  select
    qc.post_id,
    coalesce(va.upvotes_count,0) as ups,
    coalesce(va.downvotes_count,0) as downs,
    coalesce(cm.comment_count,0) as comments,
    coalesce(cm.comment_karma_nonneg,0) as comment_karma_nonneg,
    coalesce(ln.duplicate_of_count,0) as dup_cnt,
    coalesce(ln.linked_out_count,0) as link_cnt,
    coalesce(an.answers_total,0) as answers_total,
    coalesce(an.max_answer_score,0) as max_answer_score,
    coalesce(qc.score,0) as q_score,
    least(5, coalesce(qc.answercount,0)) as capped_answercount,
    case when qc.closeddate is not null then 1 else 0 end as is_closed,
    case when qc.favoritecount is null then 0 else qc.favoritecount end as favs_legacy,
    coalesce(va.favorites_count,0) as favs_votes
  from question_core qc
  left join votes_agg va on va.postid = qc.post_id
  left join comments_agg cm on cm.postid = qc.post_id
  left join links_agg ln on ln.postid = qc.post_id
  left join answers_core an on an.question_id = qc.post_id
),
ranked_questions as (
  select
    qc.post_id,
    qc.title,
    oe.displayname as owner_name,
    oe.rep_bucket,
    oe.reputation,
    oe.total_badges,
    oe.website_host,
    coalesce(tt.top_two_tags, '(no tags)') as top_tags,
    qs.ups, qs.downs, qs.comments, qs.comment_karma_nonneg,
    qs.dup_cnt, qs.link_cnt, qs.answers_total, qs.max_answer_score, qs.q_score,
    qs.capped_answercount, qs.is_closed, qs.favs_legacy, qs.favs_votes,
    aw.lifetime_hours, aw.last_event_after_hours,
    round( (qs.ups - 0.8*qs.downs)
           + 0.3*qs.comments
           + 0.1*qs.comment_karma_nonneg
           + 0.5*qs.link_cnt
           - 2.0*qs.dup_cnt
           + 0.4*qs.answers_total
           + 0.6*greatest(qs.max_answer_score, 0)
           + 0.002*coalesce(qc.viewcount,0)
           + 0.3*qs.favs_votes
           + 0.2*qs.favs_legacy
           + case when qs.is_closed = 1 then -5 else 0 end
           + case when aw.lifetime_hours > 24 then 1 else 0 end
         , 2) as quality_score,
    row_number() over (
      partition by oe.rep_bucket
      order by
        (qs.ups - qs.downs) desc,
        qs.answers_total desc,
        aw.lifetime_hours desc,
        qc.post_id
    ) as rank_in_bucket,
    dense_rank() over (order by
      (qs.ups - 0.8*qs.downs)
      + 0.3*qs.comments
      + 0.5*qs.link_cnt
      - 2.0*qs.dup_cnt
      + 0.4*qs.answers_total
      + 0.6*greatest(qs.max_answer_score, 0)
      + 0.002*coalesce(qc.viewcount,0)
      + 0.3*qs.favs_votes
      + 0.2*qs.favs_legacy
      + case when qs.is_closed = 1 then -5 else 0 end
      + case when aw.lifetime_hours > 24 then 1 else 0 end
      desc
    ) as global_rank
  from question_core qc
  left join owner_enriched oe on oe.post_id = qc.post_id
  left join quality_scores qs on qs.post_id = qc.post_id
  left join activity_windows aw on aw.post_id = qc.post_id
  left join top2_tags tt on tt.post_id = qc.post_id
),
dupe_graph as (
  select
    ra.post_id,
    count(pl2.id) as dup_inbound_count
  from recent_activity ra
  left join postlinks pl2
    on pl2.relatedpostid = ra.post_id and pl2.linktypeid = 3
  where ra.posttypeid = 1
  group by ra.post_id
),
null_diagnostics as (
  select
    rq.post_id,
    case when rq.owner_name is null then 1 else 0 end as owner_missing,
    case when rq.top_tags = '(no tags)' then 1 else 0 end as tags_missing
  from ranked_questions rq
),
finalized as (
  select
    rq.post_id,
    rq.global_rank,
    rq.rank_in_bucket,
    rq.rep_bucket,
    rq.owner_name,
    rq.reputation,
    rq.total_badges,
    rq.website_host,
    rq.title,
    rq.top_tags,
    rq.quality_score,
    rq.ups, rq.downs, rq.comments, rq.link_cnt, rq.dup_cnt, rq.answers_total,
    rq.lifetime_hours,
    dg.dup_inbound_count,
    nd.owner_missing,
    nd.tags_missing
  from ranked_questions rq
  left join dupe_graph dg on dg.post_id = rq.post_id
  left join null_diagnostics nd on nd.post_id = rq.post_id
)
select *
from finalized f
where
  (
    (f.quality_score >= 5 and coalesce(f.answers_total,0) >= 1)
    or (f.global_rank <= 200 and coalesce(f.dup_inbound_count,0) = 0)
    or (
      f.rep_bucket in ('legend','veteran')
      and (coalesce(f.ups,0) - coalesce(f.downs,0)) >= 5
      and (position('how' in lower(coalesce(f.title,''))) > 0
           or position('why' in lower(coalesce(f.title,''))) > 0)
    )
  )
  and not (coalesce(f.tags_missing,0) = 1 and coalesce(f.owner_missing,0) = 1)
  and coalesce(f.website_host, '') <> 'spam.example.com'
order by
  f.global_rank,
  f.quality_score desc,
  f.post_id
limit 500;