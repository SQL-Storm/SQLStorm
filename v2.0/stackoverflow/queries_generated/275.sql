-- {"query": "275.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3003} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate::date as user_created_date,
           coalesce(nullif(trim(split_part(coalesce(u.location, ''), ',', 1)), ''), 'Unknown') as region_hint,
           row_number() over (order by u.creationdate desc, u.id) as rn
    from users u
    where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from users)
),
tag_expansion as (
    select p.id as post_id,
           unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tagname
    from posts p
    where p.posttypeid = 1
      and p.tags is not null
),
user_activity as (
    select u.id as user_id,
           count(*) filter (where p.posttypeid = 1) as questions,
           count(*) filter (where p.posttypeid = 2) as answers,
           sum(coalesce(p.score,0)) as total_post_score,
           count(distinct p.id) as total_posts,
           sum(case when p.viewcount is null then 0 else 1 end) as posts_with_views,
           max(p.creationdate) as last_post_date
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
vote_rollup as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
           sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    where v.creationdate >= (select coalesce(min(creationdate), now() - interval '100 years') from votes)
    group by v.postid
),
question_core as (
    select q.id as question_id,
           q.owneruserid as asker_id,
           q.creationdate,
           q.score,
           q.viewcount,
           q.favoritecount,
           q.acceptedanswerid,
           q.title,
           q.tags,
           count(a.id) as answer_count,
           max(a.score) as max_answer_score
    from posts q
    left join posts a on a.parentid = q.id and a.posttypeid = 2
    where q.posttypeid = 1
    group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.favoritecount, q.acceptedanswerid, q.title, q.tags
),
accept_info as (
    select qa.parentid as question_id,
           qa.id as answer_id,
           qa.owneruserid as answerer_id,
           qa.score as accepted_answer_score
    from posts qa
    where qa.posttypeid = 2
      and exists (
          select 1 from posts q
          where q.id = qa.parentid and q.acceptedanswerid = qa.id
      )
),
close_info as (
    select ph.postid as question_id,
           min(ph.creationdate) as first_close_date,
           max(case when ph.posthistorytypeid = 10 then ph.comment end) as close_reason_id_raw,
           max(case when ph.posthistorytypeid = 10 then ph.text end) as close_payload_json
    from posthistory ph
    where ph.posthistorytypeid in (10)
    group by ph.postid
),
duplicate_links as (
    select pl.postid as dup_question_id,
           pl.relatedpostid as original_question_id
    from postlinks pl
    where pl.linktypeid = 3
),
tag_popularity as (
    select te.tagname,
           count(distinct te.post_id) as question_count_with_tag
    from tag_expansion te
    group by te.tagname
),
user_tag_mix as (
    select q.asker_id as user_id,
           te.tagname,
           count(*) as questions_with_tag
    from question_core q
    join tag_expansion te on te.post_id = q.question_id
    group by q.asker_id, te.tagname
),
ranked_user_tags as (
    select utm.user_id,
           utm.tagname,
           utm.questions_with_tag,
           row_number() over (partition by utm.user_id order by utm.questions_with_tag desc, utm.tagname) as tag_rank
    from user_tag_mix utm
),
post_engagement as (
    select qc.question_id,
           coalesce(v.upvotes,0) as upvotes,
           coalesce(v.downvotes,0) as downvotes,
           coalesce(v.favorites,0) as favorites_votes,
           coalesce(v.bounty_total,0) as bounty_awarded,
           (coalesce(v.upvotes,0) - coalesce(v.downvotes,0)) as net_votes,
           case when qc.viewcount is null or qc.viewcount = 0 then null
                else round((coalesce(v.upvotes,0)::numeric - coalesce(v.downvotes,0)::numeric) / qc.viewcount, 6)
           end as net_vote_per_view
    from question_core qc
    left join vote_rollup v on v.postid = qc.question_id
),
region_agg as (
    select ru.region_hint,
           count(*) as users_in_region,
           avg(ru.reputation) as avg_rep_region
    from recent_users ru
    group by ru.region_hint
),
user_badge_mix as (
    select b.userid,
           sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
           sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
           sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
    from badges b
    group by b.userid
),
question_quality as (
    select qc.question_id,
           qc.asker_id,
           qc.creationdate,
           qc.score,
           qc.viewcount,
           qc.answer_count,
           pe.net_votes,
           pe.net_vote_per_view,
           coalesce(pe.favorites_votes,0) + coalesce(qc.favoritecount,0) as total_favorites,
           rank() over (order by coalesce(pe.net_votes,0) desc, qc.viewcount desc, qc.creationdate desc) as popularity_rank
    from question_core qc
    left join post_engagement pe on pe.question_id = qc.question_id
),
user_summary as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           ua.questions,
           ua.answers,
           ua.total_post_score,
           ua.total_posts,
           coalesce(ub.gold_badges,0) as gold_badges,
           coalesce(ub.silver_badges,0) as silver_badges,
           coalesce(ub.bronze_badges,0) as bronze_badges,
           coalesce(ub.tag_badges,0) as tag_badges,
           ru.region_hint,
           ra.avg_rep_region,
           case when ua.total_posts > 0 then ua.total_post_score::numeric / ua.total_posts else null end as avg_post_score
    from users u
    left join user_activity ua on ua.user_id = u.id
    left join user_badge_mix ub on ub.userid = u.id
    left join recent_users ru on ru.user_id = u.id
    left join region_agg ra on ra.region_hint = ru.region_hint
),
question_flags as (
    select q.question_id,
           case when ci.first_close_date is not null then 1 else 0 end as was_closed,
           case when dl.original_question_id is not null then 1 else 0 end as was_marked_duplicate,
           ci.close_reason_id_raw,
           ci.first_close_date
    from question_core q
    left join close_info ci on ci.question_id = q.question_id
    left join duplicate_links dl on dl.dup_question_id = q.question_id
),
title_metrics as (
    select q.question_id,
           length(coalesce(q.title,'')) as title_length,
           length(regexp_replace(coalesce(q.title,''), '\s+', '', 'g')) as title_nonspace_length,
           (regexp_matches(coalesce(q.title,''), '^\[|\]$')) is not null as has_bracket_ends
    from question_core q
),
tag_focus as (
    select q.question_id,
           count(*) as tag_count,
           bool_or(lower(te.tagname) like any(array['%beginner%','%homework%','%help%'])) as has_help_tags
    from question_core q
    left join tag_expansion te on te.post_id = q.question_id
    group by q.question_id
),
accepted_latency as (
    select q.question_id,
           case when q.acceptedanswerid is null then null
                else (select a.creationdate - q.creationdate
                      from posts a
                      where a.id = q.acceptedanswerid)
           end as time_to_accept
    from question_core q
),
final_candidate as (
    select qq.question_id,
           qq.asker_id,
           us.displayname as asker_name,
           us.reputation as asker_rep,
           us.avg_post_score,
           us.gold_badges,
           us.silver_badges,
           us.bronze_badges,
           us.tag_badges,
           us.region_hint,
           qq.score as q_score,
           qq.viewcount as q_views,
           qq.answer_count,
           qq.total_favorites,
           qq.net_votes,
           qq.net_vote_per_view,
           qq.popularity_rank,
           qf.was_closed,
           qf.was_marked_duplicate,
           qf.close_reason_id_raw,
           tm.title_length,
           tm.title_nonspace_length,
           tf.tag_count,
           tf.has_help_tags,
           al.time_to_accept,
           ai.accepted_answer_score,
           coalesce(ai.accepted_answer_score, 0) - coalesce(qq.score, 0) as accept_vs_question_score_delta
    from question_quality qq
    left join user_summary us on us.user_id = qq.asker_id
    left join question_flags qf on qf.question_id = qq.question_id
    left join title_metrics tm on tm.question_id = qq.question_id
    left join tag_focus tf on tf.question_id = qq.question_id
    left join accepted_latency al on al.question_id = qq.question_id
    left join accept_info ai on ai.question_id = qq.question_id
),
ranked as (
    select fc.*,
           dense_rank() over (
             order by
               coalesce(fc.net_vote_per_view, -999)::numeric desc,
               coalesce(fc.q_views, 0) desc,
               coalesce(fc.answer_count, 0) desc,
               coalesce(fc.total_favorites, 0) desc,
               coalesce(fc.asker_rep, 0) desc
           ) as overall_rank,
           row_number() over (partition by coalesce(fc.region_hint, 'Unknown') order by coalesce(fc.net_votes, -999) desc, fc.q_views desc) as regional_rank
    from final_candidate fc
),
cross_region as (
    select r1.question_id as qid_a,
           r2.question_id as qid_b,
           r1.region_hint as region_a,
           r2.region_hint as region_b,
           r1.overall_rank + r2.overall_rank as combined_rank
    from ranked r1
    join ranked r2
      on r1.question_id <> r2.question_id
     and r1.region_hint is not distinct from r2.region_hint
     and r1.overall_rank <= 50
     and r2.overall_rank <= 50
)
select
    r.question_id,
    r.asker_id,
    r.asker_name,
    r.asker_rep,
    r.region_hint,
    r.q_score,
    r.q_views,
    r.answer_count,
    r.total_favorites,
    r.net_votes,
    r.net_vote_per_view,
    r.popularity_rank,
    r.was_closed,
    r.was_marked_duplicate,
    r.close_reason_id_raw,
    r.title_length,
    r.title_nonspace_length,
    r.tag_count,
    r.has_help_tags,
    extract(epoch from r.time_to_accept) as time_to_accept_seconds,
    r.accepted_answer_score,
    r.accept_vs_question_score_delta,
    r.overall_rank,
    r.regional_rank,
    greatest(coalesce(r.net_votes, -999), coalesce(r.q_score, -999)) as highlight_metric,
    case
        when r.was_marked_duplicate = 1 then 'DUP'
        when r.was_closed = 1 then 'CLOSED'
        when r.accepted_answer_score is not null then 'ACCEPTED'
        else 'OPEN'
    end as status_label,
    coalesce((
        select min(cr.combined_rank)
        from cross_region cr
        where cr.qid_a = r.question_id or cr.qid_b = r.question_id
    ), null) as best_pairing_combined_rank
from ranked r
where (
        r.was_closed = 0
        or (r.was_closed = 1 and r.q_views >= (
            select percentile_disc(0.75) within group (order by coalesce(q.viewcount,0))
            from question_core q
        ))
      )
  and coalesce(r.tag_count,0) between 1 and 10
  and (r.net_votes is not null or r.q_score >= 0)
  and (
        exists (
            select 1 from ranked_user_tags rut
            where rut.user_id = r.asker_id
              and rut.tag_rank <= 3
        )
        or r.gold_badges >= 1
      )
order by r.overall_rank, r.question_id
limit 500;