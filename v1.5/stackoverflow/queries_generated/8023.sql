-- {"query": "8023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2778} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
           date_trunc('month', u.creationdate) as signup_month,
           row_number() over (partition by coalesce(nullif(trim(u.location), ''), 'Unknown') order by u.reputation desc, u.id) as rn_loc_rep
    from users u
    where u.creationdate >= now() - interval '3 years'
),
question_posts as (
    select p.id,
           p.owneruserid,
           p.creationdate,
           p.score,
           p.viewcount,
           p.favoritecount,
           p.commentcount,
           p.title,
           p.tags,
           p.acceptedanswerid,
           p.closeddate,
           p.lastactivitydate
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select p.id,
           p.parentid,
           p.owneruserid,
           p.creationdate,
           p.score as answer_score
    from posts p
    where p.posttypeid = 2
),
q_activity as (
    select q.id as question_id,
           q.owneruserid as asker_id,
           q.creationdate as question_created,
           q.score as question_score,
           q.viewcount,
           q.favoritecount,
           q.commentcount,
           q.acceptedanswerid,
           q.closeddate,
           q.lastactivitydate,
           -- tag array; handle possible nulls and malformed tags
           case
               when q.tags is null then array[]::varchar[]
               when length(q.tags) < 2 then array[]::varchar[]
               else string_to_array(substring(q.tags, 2, length(q.tags) - 2), '><')
           end as tag_arr
    from question_posts q
),
answer_stats as (
    select a.parentid as question_id,
           count(*) as answer_count,
           avg(a.answer_score)::numeric(12,4) as avg_answer_score,
           max(a.answer_score) as max_answer_score,
           min(a.answer_score) as min_answer_score,
           sum(case when a.answer_score > 0 then 1 else 0 end) as positive_answers
    from answer_posts a
    group by a.parentid
),
accepted_answer_age as (
    select q.id as question_id,
           qa.creationdate as answer_created,
           q.creationdate as question_created,
           extract(epoch from (qa.creationdate - q.creationdate))::bigint as seconds_to_first_answer
    from posts q
    join posts qa
      on qa.parentid = q.id
     and qa.posttypeid = 2
    where q.posttypeid = 1
      and not exists (
          select 1
          from posts qa2
          where qa2.parentid = q.id
            and qa2.posttypeid = 2
            and qa2.creationdate < qa.creationdate
      )
),
per_tag_metrics as (
    select unnest(qa.tag_arr) as tag_name,
           qa.question_id,
           qa.asker_id,
           qa.question_score,
           qa.viewcount,
           qa.favoritecount,
           qa.commentcount
    from q_activity qa
),
tag_agg as (
    select t.tag_name,
           count(distinct t.question_id) as questions,
           avg(t.question_score)::numeric(12,4) as avg_q_score,
           percentile_cont(0.5) within group (order by t.question_score) as p50_q_score,
           avg(nullif(t.viewcount,0))::numeric(12,4) as avg_views_nonzero,
           sum(case when t.favoritecount is null then 0 else t.favoritecount end) as total_favs,
           sum(case when t.commentcount > 3 then 1 else 0 end) as questions_with_many_comments
    from per_tag_metrics t
    group by t.tag_name
),
user_badge_class as (
    select b.userid,
           max(case when b.class = 1 then 1 else 0 end) as has_gold,
           max(case when b.class = 2 then 1 else 0 end) as has_silver,
           max(case when b.class = 3 then 1 else 0 end) as has_bronze,
           count(*) as total_badges
    from badges b
    group by b.userid
),
votes_q as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_legacy,
           sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    group by v.postid
),
dup_links as (
    select pl.postid as dup_post_id,
           pl.relatedpostid as original_post_id,
           pl.creationdate as dup_marked_at
    from postlinks pl
    where pl.linktypeid = 3
),
close_events as (
    select ph.postid,
           min(ph.creationdate) as first_close_at,
           max(ph.creationdate) as last_close_at,
           count(*) filter (where ph.posthistorytypeid = 10) as close_events,
           max(case when ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+' then ph.comment::int end) as last_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
questions_with_user as (
    select qa.question_id,
           qa.asker_id,
           ru.displayname,
           ru.reputation,
           ru.location_norm,
           ru.signup_month,
           ru.rn_loc_rep,
           qa.question_created,
           qa.question_score,
           qa.viewcount,
           qa.favoritecount,
           qa.commentcount,
           qa.acceptedanswerid,
           qa.closeddate,
           qa.lastactivitydate
    from q_activity qa
    left join recent_users ru
      on ru.user_id = qa.asker_id
),
scored_questions as (
    select qwu.*,
           coalesce(vq.upvotes,0) as upvotes,
           coalesce(vq.downvotes,0) as downvotes,
           coalesce(vq.favorites_legacy,0) as favorites_legacy,
           coalesce(vq.bounty_total,0) as bounty_total,
           coalesce(asg.answer_count,0) as answer_count,
           asg.avg_answer_score,
           asg.max_answer_score,
           asg.min_answer_score,
           case when qwu.acceptedanswerid is not null then 1 else 0 end as has_accepted,
           ca.seconds_to_first_answer,
           cl.first_close_at,
           cl.last_close_at,
           cl.close_events,
           cl.last_close_reason_id,
           dl.original_post_id as duplicate_of
    from questions_with_user qwu
    left join votes_q vq on vq.postid = qwu.question_id
    left join answer_stats asg on asg.question_id = qwu.question_id
    left join accepted_answer_age ca on ca.question_id = qwu.question_id
    left join close_events cl on cl.postid = qwu.question_id
    left join dup_links dl on dl.dup_post_id = qwu.question_id
),
scored_with_rank as (
    select s.*,
           (coalesce(s.question_score,0)
            + coalesce(s.upvotes,0)
            - coalesce(s.downvotes,0)
            + least(coalesce(s.viewcount,0)/100, 50)
            + coalesce(case when s.has_accepted = 1 then 15 else 0 end, 0)
            + coalesce(case when s.bounty_total > 0 then 5 else 0 end, 0)
            + coalesce(case when s.close_events > 0 then -25 else 0 end, 0)
           )::numeric(12,2) as composite_score,
           row_number() over (partition by coalesce(s.location_norm,'Unknown') order by
                              (coalesce(s.question_score,0)
                               + coalesce(s.upvotes,0)
                               - coalesce(s.downvotes,0)
                               + least(coalesce(s.viewcount,0)/100, 50)
                               + coalesce(case when s.has_accepted = 1 then 15 else 0 end, 0)
                               + coalesce(case when s.bounty_total > 0 then 5 else 0 end, 0)
                               + coalesce(case when s.close_events > 0 then -25 else 0 end, 0)
                              ) desc,
                              s.question_id) as rn_loc_score,
           dense_rank() over (order by coalesce(s.reputation, -1) desc) as rep_rank_global
    from scored_questions s
),
tag_expansion as (
    select sq.question_id,
           unnest(
             case
               when p.tags is null or length(p.tags) < 2 then array['untagged']
               else string_to_array(substring(p.tags, 2, length(p.tags) - 2), '><')
             end
           ) as tag_name
    from scored_with_rank sq
    join posts p on p.id = sq.question_id
),
top_tag_by_question as (
    select te.question_id,
           ta.tag_name,
           ta.questions,
           row_number() over (partition by te.question_id order by ta.questions desc, ta.tag_name) as rn
    from tag_expansion te
    join tag_agg ta on ta.tag_name = te.tag_name
),
final_enriched as (
    select s.*,
           (select string_agg(tn.tag_name, ',' order by tn.tag_name)
            from tag_expansion tn
            where tn.question_id = s.question_id) as tag_list,
           tt.tag_name as primary_tag,
           tt.questions as primary_tag_popularity
    from scored_with_rank s
    left join top_tag_by_question tt
      on tt.question_id = s.question_id
     and tt.rn = 1
),
recent_vs_historic as (
    select question_id, 'recent' as bucket from final_enriched fe where fe.question_created >= now() - interval '6 months'
    union all
    select question_id, 'historic' as bucket from final_enriched fe where fe.question_created <  now() - interval '6 months'
),
bucket_counts as (
    select bucket, count(*) as cnt
    from recent_vs_historic
    group by bucket
),
location_quality as (
    select coalesce(location_norm,'Unknown') as location_norm,
           avg(composite_score)::numeric(12,2) as avg_composite_by_location,
           count(*) as questions_in_location
    from final_enriched
    group by coalesce(location_norm,'Unknown')
)
select
    fe.question_id,
    coalesce(fe.displayname, '(anonymous)') as asker_displayname,
    coalesce(fe.location_norm, 'Unknown') as location,
    fe.rep_rank_global,
    fe.rn_loc_rep,
    fe.rn_loc_score,
    fe.reputation,
    fe.question_created,
    fe.lastactivitydate,
    fe.question_score,
    fe.upvotes,
    fe.downvotes,
    fe.viewcount,
    fe.answer_count,
    fe.avg_answer_score,
    fe.max_answer_score,
    fe.min_answer_score,
    fe.has_accepted,
    fe.seconds_to_first_answer,
    coalesce(fe.close_events,0) as close_events,
    case
      when fe.last_close_reason_id between 100 and 199 then 'current'
      when fe.last_close_reason_id between 1 and 99 then 'legacy'
      when fe.last_close_reason_id is null then 'none'
      else 'other'
    end as close_reason_category,
    fe.duplicate_of,
    fe.composite_score,
    fe.tag_list,
    fe.primary_tag,
    fe.primary_tag_popularity,
    lq.avg_composite_by_location,
    lq.questions_in_location,
    coalesce(bc_recent.cnt,0) as recent_questions_count,
    coalesce(bc_hist.cnt,0) as historic_questions_count
from final_enriched fe
left join location_quality lq
  on lq.location_norm = coalesce(fe.location_norm,'Unknown')
left join bucket_counts bc_recent on bc_recent.bucket = 'recent'
left join bucket_counts bc_hist   on bc_hist.bucket   = 'historic'
where (
         fe.primary_tag is null
         or fe.primary_tag not ilike any (array['%discussion%','%meta%'])
      )
  and (
         fe.viewcount is null
         or fe.viewcount > 0
      )
  and (
         fe.reputation is null
         or fe.reputation >= 1
      )
order by fe.composite_score desc nulls last, fe.question_id
limit 500;