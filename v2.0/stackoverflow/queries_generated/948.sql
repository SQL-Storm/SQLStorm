-- {"query": "948.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3211} 
with recent_posts as (
  select
    p.id,
    p.posttypeid,
    p.creationdate,
    p.owneruserid,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.answercount,
    p.commentcount,
    p.favoritecount,
    p.acceptedanswerid,
    coalesce(p.ownerdisplayname, u.displayname) as owner_name,
    u.reputation,
    u.location
  from posts p
  left join users u on u.id = p.owneruserid
  where p.creationdate >= (select max(creationdate) - interval '90 days' from posts)
),
engagement as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
    count(*) filter (where v.votetypeid in (2,3,5,8,9)) as interaction_count,
    min(v.creationdate) filter (where v.votetypeid in (2,3,5,8,9)) as first_interaction_at,
    max(v.creationdate) filter (where v.votetypeid in (2,3,5,8,9)) as last_interaction_at
  from votes v
  group by v.postid
),
comment_stats as (
  select
    c.postid,
    count(*) as comments,
    max(c.score) as max_comment_score,
    avg(c.score) as avg_comment_score,
    max(c.creationdate) as last_comment_at
  from comments c
  group by c.postid
),
linkage as (
  select
    pl.postid,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_count,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_count,
    count(*) as total_links,
    bool_or(pl.linktypeid = 3) as has_dup_flag
  from postlinks pl
  group by pl.postid
),
history_flags as (
  select
    ph.postid,
    sum(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as close_events,
    sum(case when ph.posthistorytypeid in (11) then 1 else 0 end) as reopen_events,
    sum(case when ph.posthistorytypeid in (12) then 1 else 0 end) as delete_events,
    sum(case when ph.posthistorytypeid in (13) then 1 else 0 end) as undelete_events,
    sum(case when ph.posthistorytypeid in (19) then 1 else 0 end) as protect_events,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (10,11,12,13,19,35)) as last_moderation_at,
    count(*) filter (where ph.posthistorytypeid in (24)) as suggested_edits_applied
  from posthistory ph
  group by ph.postid
),
accepted_answers as (
  select
    q.id as question_id,
    a.id as answer_id,
    a.owneruserid as answerer_id,
    a.score as answer_score,
    a.creationdate as answer_created,
    a.lastactivitydate as answer_last_activity
  from posts q
  join posts a on a.id = q.acceptedanswerid
),
user_badge_summary as (
  select
    b.userid,
    count(*) as total_badges,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
tag_unpivot as (
  select
    p.id as postid,
    lower(trim(tg)) as tag
  from recent_posts p
  cross join lateral unnest(
    case
      when p.tags is null then array[]::varchar[]
      else string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
    end
  ) as tg
),
tag_stats as (
  select
    tu.postid,
    count(*) as tag_count,
    string_agg(distinct tu.tag, ',' order by tu.tag) as tag_list,
    max(case when tu.tag in ('sql','postgresql','mysql') then 1 else 0 end) as has_db_tag
  from tag_unpivot tu
  group by tu.postid
),
ranked_posts as (
  select
    rp.*,
    coalesce(e.upvotes,0) as upvotes,
    coalesce(e.downvotes,0) as downvotes,
    coalesce(e.favorites,0) as favorites,
    coalesce(e.bounty_total,0) as bounty_total,
    e.interaction_count,
    e.first_interaction_at,
    e.last_interaction_at,
    coalesce(cs.comments,0) as comments,
    cs.max_comment_score,
    cs.avg_comment_score,
    cs.last_comment_at,
    coalesce(lk.linked_count,0) as linked_count,
    coalesce(lk.duplicate_count,0) as duplicate_count,
    lk.total_links,
    coalesce(lk.has_dup_flag,false) as has_dup_flag,
    coalesce(hf.close_events,0) as close_events,
    coalesce(hf.reopen_events,0) as reopen_events,
    coalesce(hf.delete_events,0) as delete_events,
    coalesce(hf.undelete_events,0) as undelete_events,
    coalesce(hf.protect_events,0) as protect_events,
    hf.last_moderation_at,
    coalesce(hf.suggested_edits_applied,0) as suggested_edits_applied,
    ts.tag_count,
    ts.tag_list,
    ts.has_db_tag,
    case
      when rp.viewcount is null or rp.viewcount = 0 then null
      else round((coalesce(e.upvotes,0) - coalesce(e.downvotes,0))::numeric / nullif(rp.viewcount,0), 6)
    end as score_per_view,
    case
      when rp.answercount is null or rp.answercount = 0 then null
      else round(coalesce(e.upvotes,0)::numeric / nullif(rp.answercount,0), 6)
    end as upvotes_per_answer,
    extract(epoch from (coalesce(e.last_interaction_at, rp.creationdate) - rp.creationdate)) / 3600.0 as hours_to_last_interaction,
    extract(epoch from (coalesce(cs.last_comment_at, rp.creationdate) - rp.creationdate)) / 3600.0 as hours_to_last_comment
  from recent_posts rp
  left join engagement e on e.postid = rp.id
  left join comment_stats cs on cs.postid = rp.id
  left join linkage lk on lk.postid = rp.id
  left join history_flags hf on hf.postid = rp.id
  left join tag_stats ts on ts.postid = rp.id
),
user_context as (
  select
    u.id as userid,
    u.displayname,
    u.reputation,
    u.creationdate as user_created,
    u.lastaccessdate,
    u.views as profile_views,
    u.upvotes as cast_upvotes,
    u.downvotes as cast_downvotes,
    ub.total_badges,
    ub.gold_badges,
    ub.silver_badges,
    ub.bronze_badges,
    ub.last_badge_at
  from users u
  left join user_badge_summary ub on ub.userid = u.id
),
question_answer_mix as (
  select
    rp.id,
    rp.posttypeid,
    case when rp.posttypeid = 1 then 1 else 0 end as is_question,
    case when rp.posttypeid = 2 then 1 else 0 end as is_answer,
    aa.answer_id,
    aa.answerer_id,
    aa.answer_score,
    aa.answer_created,
    aa.answer_last_activity
  from ranked_posts rp
  left join accepted_answers aa on aa.question_id = rp.id
),
post_quality as (
  select
    rp.id,
    rp.title,
    rp.owner_name,
    rp.reputation,
    rp.location,
    rp.score,
    rp.viewcount,
    rp.tag_list,
    rp.has_db_tag,
    rp.upvotes,
    rp.downvotes,
    rp.favorites,
    rp.comments,
    rp.duplicate_count,
    rp.close_events,
    rp.delete_events,
    rp.protect_events,
    rp.suggested_edits_applied,
    rp.score_per_view,
    rp.upvotes_per_answer,
    rp.hours_to_last_interaction,
    rp.hours_to_last_comment,
    qam.is_question,
    qam.is_answer,
    qam.answer_id,
    qam.answerer_id,
    qam.answer_score,
    case
      when rp.title is null then 0
      when length(regexp_replace(lower(rp.title), '\s+', '', 'g')) = 0 then 0
      else 1
    end as has_nonempty_title,
    case
      when rp.tags is null then 0
      when rp.tag_count >= 3 then 1
      else 0
    end as has_many_tags,
    case
      when rp.viewcount >= 10000 and rp.score >= 10 then 'evergreen'
      when rp.viewcount >= 2000 and rp.score >= 0 then 'readable'
      when rp.delete_events > 0 then 'controversial'
      else 'niche'
    end as popularity_bucket
  from ranked_posts rp
  left join question_answer_mix qam on qam.id = rp.id
),
dedup as (
  select
    pq.*,
    row_number() over (
      partition by coalesce(nullif(trim(lower(pq.title)),''),
                            'untitled') order by pq.score desc nulls last, pq.viewcount desc nulls last, pq.id
    ) as title_rank
  from post_quality pq
),
filtered as (
  select *
  from dedup
  where (has_db_tag = 1 or has_many_tags = 1)
    and coalesce(score_per_view, 0) >= -0.001
    and coalesce(upvotes,0) >= coalesce(downvotes,0)
    and (duplicate_count = 0 or close_events = 0)
    and title_rank = 1
),
scored as (
  select
    f.*,
    /* composite benchmark score with mixed arithmetic, null logic, and weighting */
    round((
      coalesce(score::numeric,0) * 1.0
      + coalesce(upvotes,0) * 2.5
      - coalesce(downvotes,0) * 3.0
      + coalesce(favorites,0) * 1.2
      + coalesce(comments,0) * 0.25
      + coalesce(duplicate_count,0) * -4.0
      + coalesce(close_events,0) * -6.0
      + coalesce(delete_events,0) * -10.0
      + coalesce(protect_events,0) * 1.0
      + coalesce(suggested_edits_applied,0) * 0.75
      + coalesce(viewcount,0) * 0.01
      + coalesce(answer_score,0) * 1.75
      + case when is_question = 1 then 5 else 0 end
      + case when has_nonempty_title = 1 then 2 else -2 end
      + case when has_many_tags = 1 then 1 else 0 end
      + case popularity_bucket
          when 'evergreen' then 25
          when 'readable' then 10
          when 'controversial' then -8
          else 0
        end
      + coalesce(100.0 * score_per_view, 0)
      - coalesce(0.5 * hours_to_last_interaction, 0)
      - coalesce(0.25 * hours_to_last_comment, 0)
    )::numeric, 3) as benchmark_score
  from filtered f
),
with_user as (
  select
    s.*,
    uc.displayname as author_name,
    uc.reputation as author_reputation,
    uc.total_badges as author_badges,
    uc.gold_badges as author_gold,
    uc.silver_badges as author_silver,
    uc.bronze_badges as author_bronze
  from scored s
  left join user_context uc on uc.userid = (
    select owneruserid from posts p where p.id = s.id
  )
),
ranked as (
  select
    wu.*,
    ntile(10) over (order by benchmark_score desc nulls last) as decile,
    dense_rank() over (order by benchmark_score desc nulls last) as dense_rank_global,
    row_number() over (partition by has_db_tag order by benchmark_score desc nulls last, viewcount desc nulls last) as within_tag_rownum
  from with_user wu
)
select
  r.id as post_id,
  r.title,
  r.author_name,
  r.author_reputation,
  r.author_badges,
  r.author_gold,
  r.author_silver,
  r.author_bronze,
  r.reputation as owner_reputation_at_post_time,
  r.location,
  r.tag_list,
  r.viewcount,
  r.score,
  r.upvotes,
  r.downvotes,
  r.favorites,
  r.comments,
  r.duplicate_count,
  r.close_events,
  r.delete_events,
  r.protect_events,
  r.suggested_edits_applied,
  r.score_per_view,
  r.upvotes_per_answer,
  r.hours_to_last_interaction,
  r.hours_to_last_comment,
  r.popularity_bucket,
  r.benchmark_score,
  r.decile,
  r.dense_rank_global,
  r.within_tag_rownum,
  case when r.within_tag_rownum <= 50 then 'TOP' else 'REST' end as segment
from ranked r
where r.decile in (1,2,3,4,5,6,7,8,9,10)
  and (r.benchmark_score is not null or r.upvotes > 0)
order by r.benchmark_score desc nulls last, r.viewcount desc nulls last, r.id asc
limit 500;