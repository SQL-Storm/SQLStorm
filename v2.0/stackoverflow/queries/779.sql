-- {"query": "779.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3072}
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown.host') as website_host
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
tagged_questions as (
    select p.id as question_id,
           p.owneruserid,
           p.creationdate,
           p.score,
           p.viewcount,
           p.answercount,
           p.title,
           p.tags,
           (select count(*) from comments c where c.postid = p.id) as total_comments
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
),
dup_links as (
    select pl.postid as duplicate_id,
           pl.relatedpostid as original_id
    from postlinks pl
    where pl.linktypeid = 3
),
activity_cte as (
    select ph.postid,
           count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_events,
           count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35,36)) as mod_events,
           min(ph.creationdate) as first_event_at,
           max(ph.creationdate) as last_event_at
    from posthistory ph
    where ph.creationdate >= (select max(creationdate) - interval '365 days' from posthistory)
    group by ph.postid
),
votes_agg as (
    select v.postid,
           count(*) filter (where v.votetypeid = 2) as upvotes,
           count(*) filter (where v.votetypeid = 3) as downvotes,
           count(*) filter (where v.votetypeid = 5) as favorites,
           count(*) filter (where v.votetypeid in (8,9)) as bounty_events,
           sum(coalesce(v.bountyamount,0)) as bounty_total
    from votes v
    where v.creationdate >= (select max(creationdate) - interval '365 days' from votes)
    group by v.postid
),
user_badges as (
    select b.userid,
           count(*) as total_badges,
           count(*) filter (where b.class = 1) as gold_badges,
           count(*) filter (where b.class = 2) as silver_badges,
           count(*) filter (where b.class = 3) as bronze_badges,
           max(b.date) as last_badge_at
    from badges b
    group by b.userid
),
q_owner as (
    select tq.question_id,
           coalesce(tq.owneruserid, -1) as owner_id
    from tagged_questions tq
),
owner_user_details as (
    select q.question_id,
           ru.user_id,
           ru.displayname,
           ru.reputation,
           ru.creationdate as user_created_at,
           ru.location,
           ru.website_host
    from q_owner q
    left join recent_users ru
      on ru.user_id = q.owner_id
),
answers_stats as (
    select p.parentid as question_id,
           count(*) as answers_count,
           avg(p.score) as avg_answer_score,
           max(p.creationdate) as last_answer_at,
           sum(case when p.owneruserid is null then 1 else 0 end) as anon_answers
    from posts p
    where p.posttypeid = 2
      and p.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 2)
    group by p.parentid
),
title_quality as (
    select tq.question_id,
           length(coalesce(tq.title, '')) as title_len,
           length(regexp_replace(coalesce(tq.title,''), '[^aeiouAEIOU]', '', 'g')) as vowel_count,
           case when lower(coalesce(tq.title,'')) similar to '%([^a-z0-9]|^)how[[:space:]]+to([^a-z0-9]|%)%' then 1 else 0 end as has_how_to,
           case when lower(coalesce(tq.title,'')) like '%please%' then 1 else 0 end as has_please
    from tagged_questions tq
),
tag_explode as (
    select tq.question_id,
           unnest(string_to_array(substring(tq.tags, 2, greatest(length(tq.tags)-2,0)), '><')) as tagname
    from tagged_questions tq
    where tq.tags is not null
),
primary_tag as (
    select question_id,
           min(tagname) as primary_tag
    from tag_explode
    group by question_id
),
tag_meta as (
    select t.tagname,
           t.count as tag_total_count,
           case when t.ismoderatoronly then 1 else 0 end as is_moderator_only,
           case when t.isrequired then 1 else 0 end as is_required
    from tags t
),
q_ranked as (
    select tq.question_id,
           row_number() over (order by coalesce(tq.viewcount,0) desc, coalesce(tq.score,0) desc) as rn_views_score,
           row_number() over (order by coalesce(tq.answercount,0) desc, coalesce(tq.total_comments,0) desc) as rn_ans_comments,
           dense_rank() over (order by date_trunc('month', tq.creationdate)) as month_bucket
    from tagged_questions tq
),
nullness as (
    select tq.question_id,
           case when tq.owneruserid is null then 1 else 0 end as is_owner_null,
           case when tq.title is null or trim(tq.title) = '' then 1 else 0 end as is_title_blank
    from tagged_questions tq
),
question_core as (
    select tq.question_id,
           tq.creationdate as question_created_at,
           coalesce(tq.score, 0) as q_score,
           coalesce(tq.viewcount, 0) as q_views,
           coalesce(tq.answercount, 0) as q_answers,
           tq.total_comments
    from tagged_questions tq
),
scored as (
    select qc.question_id,
           qc.question_created_at,
           qc.q_score,
           qc.q_views,
           qc.q_answers,
           qc.total_comments,
           coalesce(va.upvotes,0) as upvotes,
           coalesce(va.downvotes,0) as downvotes,
           coalesce(va.favorites,0) as favorites,
           coalesce(va.bounty_events,0) as bounty_events,
           coalesce(va.bounty_total,0) as bounty_total,
           coalesce(ac.edit_events,0) as edit_events,
           coalesce(ac.mod_events,0) as mod_events,
           ac.first_event_at,
           ac.last_event_at
    from question_core qc
    left join votes_agg va on va.postid = qc.question_id
    left join activity_cte ac on ac.postid = qc.question_id
),
dup_flag as (
    select tq.question_id,
           case when exists (
                select 1 from dup_links d
                where d.duplicate_id = tq.question_id
           ) then 1 else 0 end as is_marked_duplicate,
           (select d.original_id from dup_links d where d.duplicate_id = tq.question_id limit 1) as original_id
    from tagged_questions tq
),
owner_enriched as (
    select oud.question_id,
           oud.user_id as owner_id,
           coalesce(oud.displayname, '[unknown]') as owner_displayname,
           coalesce(oud.reputation, -1) as owner_reputation,
           oud.user_created_at,
           coalesce(oud.location, 'Unknown') as owner_location,
           lower(oud.website_host) as website_host,
           coalesce(ub.total_badges, 0) as total_badges,
           coalesce(ub.gold_badges, 0) as gold_badges,
           coalesce(ub.silver_badges, 0) as silver_badges,
           coalesce(ub.bronze_badges, 0) as bronze_badges,
           ub.last_badge_at
    from owner_user_details oud
    left join user_badges ub on ub.userid = oud.user_id
),
final_scored as (
    select s.question_id,
           s.question_created_at,
           s.q_score,
           s.q_views,
           s.q_answers,
           s.total_comments,
           s.upvotes,
           s.downvotes,
           s.favorites,
           s.bounty_events,
           s.bounty_total,
           s.edit_events,
           s.mod_events,
           s.first_event_at,
           s.last_event_at,
           oe.owner_id,
           oe.owner_displayname,
           oe.owner_reputation,
           oe.owner_location,
           oe.website_host,
           oe.total_badges,
           oe.gold_badges,
           oe.silver_badges,
           oe.bronze_badges,
           tq.title,
           pq.primary_tag,
           tm.tag_total_count,
           tm.is_moderator_only,
           tm.is_required,
           ts.title_len,
           ts.vowel_count,
           ts.has_how_to,
           ts.has_please,
           dr.is_marked_duplicate,
           dr.original_id,
           asf.answers_count,
           asf.avg_answer_score,
           asf.last_answer_at,
           asf.anon_answers,
           nr.is_owner_null,
           nr.is_title_blank,
           qr.rn_views_score,
           qr.rn_ans_comments,
           qr.month_bucket
    from scored s
    join tagged_questions tq on tq.question_id = s.question_id
    left join owner_enriched oe on oe.question_id = s.question_id
    left join primary_tag pq on pq.question_id = s.question_id
    left join tag_meta tm on tm.tagname = pq.primary_tag
    left join title_quality ts on ts.question_id = s.question_id
    left join dup_flag dr on dr.question_id = s.question_id
    left join answers_stats asf on asf.question_id = s.question_id
    left join nullness nr on nr.question_id = s.question_id
    left join q_ranked qr on qr.question_id = s.question_id
),
scored_with_bucket as (
    select f.question_id,
           f.question_created_at,
           f.q_score,
           f.q_views,
           f.q_answers,
           f.total_comments,
           f.upvotes,
           f.downvotes,
           f.favorites,
           f.bounty_events,
           f.bounty_total,
           f.edit_events,
           f.mod_events,
           f.first_event_at,
           f.last_event_at,
           f.owner_id,
           f.owner_displayname,
           f.owner_reputation,
           f.owner_location,
           f.website_host,
           f.total_badges,
           f.gold_badges,
           f.silver_badges,
           f.bronze_badges,
           f.title,
           f.primary_tag,
           f.tag_total_count,
           f.is_moderator_only,
           f.is_required,
           f.title_len,
           f.vowel_count,
           f.has_how_to,
           f.has_please,
           f.is_marked_duplicate,
           f.original_id,
           f.answers_count,
           f.avg_answer_score,
           f.last_answer_at,
           f.anon_answers,
           f.is_owner_null,
           f.is_title_blank,
           f.rn_views_score,
           f.rn_ans_comments,
           f.month_bucket,
           (
             0.30 * ln(1 + greatest(f.q_views,0)) +
             0.25 * greatest(f.q_score,0) +
             0.15 * coalesce(f.upvotes - f.downvotes, 0) +
             0.10 * coalesce(f.favorites, 0) +
             0.10 * coalesce(f.answers_count, 0) +
             0.05 * case when f.is_marked_duplicate = 1 then -5 else 0 end +
             0.05 * case when f.is_moderator_only = 1 then -3 else 0 end
           ) as composite_score,
           case
             when f.owner_reputation >= 100000 then 'legend'
             when f.owner_reputation >= 20000 then 'elite'
             when f.owner_reputation >= 3000 then 'pro'
             when f.owner_reputation >= 500 then 'regular'
             when f.owner_reputation >= 1 then 'newbie'
             else 'anon'
           end as author_tier,
           case
             when f.primary_tag is null then 'untagged'
             when f.is_required = 1 then 'required'
             when f.is_moderator_only = 1 then 'mod-only'
             else 'normal'
           end as tag_category
    from final_scored f
),
top_per_month as (
    select question_id,
           month_bucket,
           composite_score,
           row_number() over (partition by month_bucket order by composite_score desc, q_views desc, q_score desc, question_id) as rn_top
    from scored_with_bucket
)
select
    swb.question_id,
    swb.question_created_at,
    swb.primary_tag,
    swb.title,
    swb.q_views,
    swb.q_score,
    swb.answers_count,
    swb.avg_answer_score,
    swb.total_comments,
    swb.upvotes,
    swb.downvotes,
    swb.favorites,
    swb.bounty_total,
    swb.edit_events,
    swb.mod_events,
    swb.is_marked_duplicate,
    swb.original_id,
    swb.owner_id,
    swb.owner_displayname,
    swb.owner_reputation,
    swb.owner_location,
    swb.total_badges,
    swb.gold_badges,
    swb.silver_badges,
    swb.bronze_badges,
    swb.title_len,
    swb.vowel_count,
    swb.has_how_to,
    swb.has_please,
    swb.is_owner_null,
    swb.is_title_blank,
    swb.month_bucket,
    swb.rn_views_score,
    swb.rn_ans_comments,
    swb.tag_total_count,
    swb.is_moderator_only,
    swb.is_required,
    swb.author_tier,
    swb.tag_category,
    swb.composite_score,
    coalesce(tp.rn_top, null) as rank_in_month_by_score
from scored_with_bucket swb
left join top_per_month tp
  on tp.question_id = swb.question_id
 and tp.month_bucket = swb.month_bucket
where
    (
      (swb.composite_score > 1.5 and swb.q_views > 100)
      or (swb.author_tier in ('elite','legend') and swb.q_score >= 10)
      or (swb.is_marked_duplicate = 0 and swb.answers_count >= 3 and swb.avg_answer_score >= 1)
    )
  and coalesce(swb.is_title_blank,0) = 0
  and not (swb.is_moderator_only = 1 and swb.is_required = 1)
  and (swb.primary_tag is distinct from 'discussion')
order by swb.composite_score desc, swb.q_views desc, swb.q_score desc, swb.question_id
limit 500;