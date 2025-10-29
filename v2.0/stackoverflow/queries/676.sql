-- {"query": "676.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2389}
with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm
  from users u
  where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from users)
),
badge_agg as (
  select b.userid,
         count(*) filter (where b.class = 1) as gold_cnt,
         count(*) filter (where b.class = 2) as silver_cnt,
         count(*) filter (where b.class = 3) as bronze_cnt,
         min(b.date) as first_badge_date,
         max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
question_core as (
  select p.id as question_id,
         p.owneruserid as owner_id,
         p.creationdate as q_created,
         p.score as q_score,
         p.viewcount as q_views,
         p.answercount as q_answers,
         p.title,
         p.tags,
         case when p.closeddate is not null then 1 else 0 end as is_closed
  from posts p
  where p.posttypeid = 1
),
answer_core as (
  select a.parentid as question_id,
         a.id as answer_id,
         a.owneruserid as answer_owner_id,
         a.creationdate as a_created,
         a.score as a_score
  from posts a
  where a.posttypeid = 2
),
q_activity as (
  select qc.question_id,
         count(*) as comment_count,
         max(c.creationdate) as last_comment_at
  from question_core qc
  left join comments c on c.postid = qc.question_id
  group by qc.question_id
),
q_votes as (
  select v.postid as question_id,
         count(*) filter (where v.votetypeid = 2) as up_votes,
         count(*) filter (where v.votetypeid = 3) as down_votes,
         count(*) filter (where v.votetypeid = 5) as favorite_votes,
         sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total
  from votes v
  group by v.postid
),
dup_links as (
  select pl.postid as dup_question_id,
         pl.relatedpostid as canonical_question_id,
         min(pl.creationdate) as first_dupe_link_at
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid, pl.relatedpostid
),
owner_basics as (
  select u.id as owner_id,
         u.displayname as owner_name,
         u.reputation as owner_rep,
         u.creationdate as owner_created,
         coalesce(nullif(u.location,''), 'Unknown') as owner_location
  from users u
),
answer_stats as (
  select ac.question_id,
         count(*) as answer_cnt,
         sum(case when ac.a_score > 0 then 1 else 0 end) as pos_answers,
         max(ac.a_score) as max_answer_score,
         min(ac.a_created) as first_answer_at,
         max(ac.a_created) as last_answer_at
  from answer_core ac
  group by ac.question_id
),
accepted_map as (
  select p.id as question_id,
         p.acceptedanswerid as accepted_answer_id
  from posts p
  where p.posttypeid = 1
),
posthistory_close as (
  select ph.postid as question_id,
         min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed_at,
         min(case when ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+' then cast(ph.comment as integer) end) as first_close_reason_id,
         min(ph.creationdate) filter (where ph.posthistorytypeid = 11) as first_reopened_at
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
tag_expanded as (
  select qc.question_id,
         unnest(string_to_array(substring(qc.tags, 2, greatest(length(qc.tags)-2,0)), '><')) as tag
  from question_core qc
  where qc.tags is not null and qc.tags like '<%>'
),
top_tags as (
  select tag,
         count(*) as tag_q_count,
         row_number() over (order by count(*) desc, tag) as rn
  from tag_expanded
  group by tag
),
recent_hot_questions as (
  select qc.question_id,
         qc.owner_id,
         qc.q_created,
         qc.q_score,
         qc.q_views,
         qc.q_answers,
         qc.title,
         qc.tags,
         qa.comment_count,
         qa.last_comment_at,
         qv.up_votes,
         qv.down_votes,
         qv.favorite_votes,
         qv.bounty_total,
         asx.answer_cnt,
         asx.pos_answers,
         asx.max_answer_score,
         asx.first_answer_at,
         asx.last_answer_at,
         am.accepted_answer_id,
         phc.first_closed_at,
         phc.first_close_reason_id,
         phc.first_reopened_at,
         dl.canonical_question_id,
         dl.first_dupe_link_at,
         qc.is_closed
  from question_core qc
  left join q_activity qa on qa.question_id = qc.question_id
  left join q_votes qv on qv.question_id = qc.question_id
  left join answer_stats asx on asx.question_id = qc.question_id
  left join accepted_map am on am.question_id = qc.question_id
  left join posthistory_close phc on phc.question_id = qc.question_id
  left join dup_links dl on dl.dup_question_id = qc.question_id
  where qc.q_created >= (select date_trunc('month', max(creationdate)) - interval '12 months' from posts)
),
owner_enriched as (
  select rhq.*,
         ob.owner_name,
         ob.owner_rep,
         ob.owner_created,
         ob.owner_location,
         ba.gold_cnt,
         ba.silver_cnt,
         ba.bronze_cnt,
         ba.first_badge_date,
         ba.last_badge_date
  from recent_hot_questions rhq
  left join owner_basics ob on ob.owner_id = rhq.owner_id
  left join badge_agg ba on ba.userid = rhq.owner_id
),
ranked_questions as (
  select oe.*,
         coalesce(oe.up_votes - oe.down_votes, 0) as net_votes,
         case
           when oe.accepted_answer_id is not null then 1
           when coalesce(oe.answer_cnt,0) > 0 and coalesce(oe.max_answer_score,0) >= 5 then 1
           else 0
         end as has_quality_answer,
         case when oe.first_closed_at is not null and oe.first_reopened_at is not null and oe.first_reopened_at > oe.first_closed_at then 1 else 0 end as was_reopened,
         coalesce(oe.bounty_total,0) + greatest(coalesce(oe.q_score,0),0) * 10 + coalesce(oe.favorite_votes,0) * 2 + coalesce(coalesce(oe.up_votes - oe.down_votes, 0),0) as hotness_raw,
         row_number() over (
           partition by case when oe.owner_location ilike '%united states%' then 'US' else 'NON-US' end
           order by coalesce(oe.q_views,0) desc, coalesce(coalesce(oe.up_votes - oe.down_votes,0),0) desc, oe.q_created desc
         ) as loc_rank,
         ntile(5) over (order by coalesce(oe.q_views,0) desc nulls last) as views_quintile,
         dense_rank() over (order by coalesce(
           coalesce(oe.bounty_total,0) + greatest(coalesce(oe.q_score,0),0) * 10 + coalesce(oe.favorite_votes,0) * 2 + coalesce(coalesce(oe.up_votes - oe.down_votes,0),0)
         ,0) desc) as hot_rank
  from owner_enriched oe
),
owner_peer as (
  select o1.question_id,
         o1.owner_id,
         (
           select avg(o2.q_score)
           from owner_enriched o2
           where o2.owner_id = o1.owner_id
             and o2.q_created >= o1.q_created - interval '90 days'
             and o2.q_created <= o1.q_created + interval '90 days'
         ) as owner_local_avg_qscore
  from owner_enriched o1
),
tag_pivot as (
  select rq.question_id,
         max(case when tt.tag in ('javascript','python','java','c#','php') then tt.tag end) as any_top5_tag,
         count(*) filter (where tt.tag in (select tag from top_tags where rn <= 25)) as top25_tag_hits
  from recent_hot_questions rq
  left join tag_expanded tt on tt.question_id = rq.question_id
  group by rq.question_id
)
select
  rq.question_id,
  rq.title,
  rq.tags,
  rq.q_created,
  rq.q_views,
  rq.q_score,
  rq.net_votes,
  rq.favorite_votes,
  rq.bounty_total,
  rq.answer_cnt,
  rq.accepted_answer_id,
  rq.has_quality_answer,
  rq.is_closed,
  rq.was_reopened,
  rq.owner_id,
  rq.owner_name,
  rq.owner_rep,
  rq.owner_location,
  coalesce(op.owner_local_avg_qscore, 0) as owner_local_avg_qscore,
  tp.any_top5_tag,
  tp.top25_tag_hits,
  rq.hotness_raw,
  rq.hot_rank,
  rq.loc_rank,
  rq.views_quintile,
  coalesce(rq.first_closed_at, rq.last_comment_at, rq.last_answer_at, rq.q_created) as last_significant_event,
  case
    when rq.canonical_question_id is not null then 'DUPLICATE_OF_' || cast(rq.canonical_question_id as varchar)
    when rq.first_closed_at is not null then 'CLOSED_' || coalesce(cast(rq.first_close_reason_id as varchar),'UNK')
    else 'OPEN'
  end as status_label
from ranked_questions rq
left join owner_peer op on op.question_id = rq.question_id and op.owner_id = rq.owner_id
left join tag_pivot tp on tp.question_id = rq.question_id
where
  coalesce(rq.q_views,0) > 0
  and (rq.hot_rank <= 500 or rq.views_quintile in (1,2))
  and (
    rq.owner_rep >= all (
      select coalesce(u2.reputation,0)
      from users u2
      where u2.id in (
        select distinct coalesce(p.owneruserid, -1)
        from posts p
        where p.posttypeid = 1
          and p.creationdate >= rq.q_created - interval '30 days'
          and p.creationdate < rq.q_created + interval '30 days'
      )
    )
    or rq.gold_cnt >= 1
    or (rq.silver_cnt >= 3 and rq.bronze_cnt >= 10)
  )
order by rq.hot_rank, rq.q_views desc, rq.q_created desc
limit 1000;