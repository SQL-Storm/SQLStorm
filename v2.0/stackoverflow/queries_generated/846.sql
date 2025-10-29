-- {"query": "846.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2850} 
with recent_activity as (
    select
        p.id as post_id,
        p.posttypeid,
        p.owneruserid,
        p.creationdate,
        p.lastactivitydate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        coalesce(p.answercount, 0) as answercount,
        date_trunc('month', p.creationdate) as month_bucket
    from posts p
    where p.creationdate >= now() - interval '3 years'
),
user_stats as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate as user_creation,
        coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
        u.upvotes,
        u.downvotes,
        u.views as profile_views,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        count(b.id) as total_badges,
        max(b.date) as last_badge_date
    from users u
    left join badges b on b.userid = u.id
    group by u.id, u.displayname, u.reputation, u.creationdate, u.location, u.upvotes, u.downvotes, u.views
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
        count(*) as total_votes,
        min(v.creationdate) as first_vote_at,
        max(v.creationdate) as last_vote_at
    from votes v
    where v.creationdate >= now() - interval '3 years'
    group by v.postid
),
comments_agg as (
    select
        c.postid,
        count(*) as comment_count,
        sum(greatest(c.score,0)) as comment_score_nonneg,
        max(c.creationdate) as last_commented_at
    from comments c
    where c.creationdate >= now() - interval '3 years'
    group by c.postid
),
postlinks_agg as (
    select
        pl.postid,
        sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_count,
        sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_count
    from postlinks pl
    where pl.creationdate >= now() - interval '3 years'
    group by pl.postid
),
accepted_answers as (
    select
        q.id as question_id,
        a.id as accepted_answer_id,
        a.owneruserid as accepted_owner_id,
        a.score as accepted_answer_score,
        a.creationdate as accepted_answer_date
    from posts q
    join posts a on a.id = q.acceptedanswerid
    where q.posttypeid = 1
),
tag_expansion as (
    select
        ra.post_id,
        unnest(string_to_array(substring(ra.tags, 2, length(ra.tags)-2), '><')) as tag
    from recent_activity ra
    where ra.posttypeid = 1
      and ra.tags is not null
      and length(ra.tags) > 2
),
tag_quality as (
    select
        te.tag,
        count(distinct te.post_id) as tagged_questions,
        avg(ra.score)::numeric(12,4) as avg_q_score,
        avg(ra.viewcount)::numeric(12,4) as avg_q_views,
        percentile_cont(0.9) within group (order by ra.viewcount) as p90_views
    from tag_expansion te
    join recent_activity ra on ra.post_id = te.post_id
    group by te.tag
    having count(*) > 10
),
edits_agg as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits_count,
        count(*) filter (where ph.posthistorytypeid in (10)) as closes_count,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as last_edit_at,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (10)) as last_closed_at
    from posthistory ph
    where ph.creationdate >= now() - interval '3 years'
    group by ph.postid
),
question_answer_latency as (
    select
        q.id as question_id,
        min(a.creationdate) - q.creationdate as time_to_first_answer,
        count(a.id) as answers_last_3y
    from posts q
    left join posts a on a.parentid = q.id and a.posttypeid = 2 and a.creationdate >= now() - interval '3 years'
    where q.posttypeid = 1
      and q.creationdate >= now() - interval '3 years'
    group by q.id, q.creationdate
),
user_posting_cadence as (
    select
        ra.owneruserid as user_id,
        date_trunc('month', ra.creationdate) as month_bucket,
        count(*) as posts_in_month
    from recent_activity ra
    where ra.owneruserid is not null
    group by ra.owneruserid, date_trunc('month', ra.creationdate)
),
user_cadence_stats as (
    select
        upc.user_id,
        avg(upc.posts_in_month)::numeric(12,4) as avg_posts_per_month,
        stddev_pop(upc.posts_in_month)::numeric(12,4) as sd_posts_per_month,
        max(upc.posts_in_month) as peak_posts_in_month
    from user_posting_cadence upc
    group by upc.user_id
),
post_engagement as (
    select
        ra.post_id,
        ra.posttypeid,
        ra.owneruserid,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(va.favorites,0) as favorites,
        coalesce(va.bounty_total,0) as bounty_total,
        coalesce(ca.comment_count,0) as comment_count,
        coalesce(ca.comment_score_nonneg,0) as comment_score_nonneg,
        coalesce(pa.linked_count,0) as linked_count,
        coalesce(pa.duplicate_count,0) as duplicate_count,
        coalesce(ea.edits_count,0) as edits_count,
        coalesce(ea.closes_count,0) as closes_count
    from recent_activity ra
    left join votes_agg va on va.postid = ra.post_id
    left join comments_agg ca on ca.postid = ra.post_id
    left join postlinks_agg pa on pa.postid = ra.post_id
    left join edits_agg ea on ea.postid = ra.post_id
),
post_quality_score as (
    select
        pe.post_id,
        pe.owneruserid,
        round(
            0.40 * pe.upvotes
          - 0.25 * pe.downvotes
          + 0.15 * pe.comment_count
          + 0.10 * least(pe.edits_count, 5)
          + 0.20 * pe.favorites
          + 0.05 * pe.linked_count
          - 0.30 * pe.duplicate_count
          + 0.001 * pe.bounty_total
          + case when pe.closes_count > 0 then -2.0 else 0 end
        , 4) as quality_score
    from post_engagement pe
),
user_quality_rollup as (
    select
        ra.owneruserid as user_id,
        count(*) as posts_count,
        avg(pq.quality_score)::numeric(12,4) as avg_quality_score,
        percentile_cont(0.5) within group (order by pq.quality_score) as p50_quality,
        percentile_cont(0.9) within group (order by pq.quality_score) as p90_quality,
        sum(case when pq.quality_score >= 10 then 1 else 0 end) as high_quality_posts
    from recent_activity ra
    join post_quality_score pq on pq.post_id = ra.post_id
    where ra.owneruserid is not null
    group by ra.owneruserid
),
top_user_candidates as (
    select
        us.user_id,
        us.displayname,
        us.reputation,
        us.location_norm,
        uqr.posts_count,
        uqr.avg_quality_score,
        uqr.p90_quality,
        uqr.high_quality_posts,
        ucs.avg_posts_per_month,
        ucs.sd_posts_per_month,
        us.total_badges,
        row_number() over (
            order by
                uqr.avg_quality_score desc nulls last,
                uqr.p90_quality desc nulls last,
                uqr.high_quality_posts desc,
                us.reputation desc
        ) as rn
    from user_stats us
    join user_quality_rollup uqr on uqr.user_id = us.user_id
    left join user_cadence_stats ucs on ucs.user_id = us.user_id
    where us.reputation >= 100
),
question_enrichment as (
    select
        ra.post_id,
        ra.title,
        ra.creationdate,
        ra.viewcount,
        ra.score,
        ql.time_to_first_answer,
        ql.answers_last_3y,
        aa.accepted_answer_id,
        aa.accepted_answer_score,
        case
            when ra.tags is null then 0
            when length(ra.tags) <= 2 then 0
            else cardinality(string_to_array(substring(ra.tags, 2, length(ra.tags)-2), '><'))
        end as tag_count
    from recent_activity ra
    left join question_answer_latency ql on ql.question_id = ra.post_id
    left join accepted_answers aa on aa.question_id = ra.post_id
    where ra.posttypeid = 1
),
tag_top as (
    select
        te.post_id,
        array_agg(te.tag order by tq.avg_q_views desc nulls last) as tags_by_views,
        array_agg(te.tag order by tq.avg_q_score desc nulls last) as tags_by_score
    from tag_expansion te
    left join tag_quality tq on tq.tag = te.tag
    group by te.post_id
),
final as (
    select
        qe.post_id,
        qe.title,
        qe.creationdate,
        qe.viewcount,
        qe.score as question_score,
        qe.tag_count,
        coalesce((select tags_by_views[1] from tag_top tt where tt.post_id = qe.post_id), null) as top_tag_by_views,
        coalesce((select tags_by_score[1] from tag_top tt where tt.post_id = qe.post_id), null) as top_tag_by_score,
        pq.quality_score as engagement_quality,
        extract(epoch from qe.time_to_first_answer)::bigint as seconds_to_first_answer,
        qe.answers_last_3y,
        case when qe.accepted_answer_id is null then 'No' else 'Yes' end as has_accepted_answer,
        coalesce(qe.accepted_answer_score, 0) as accepted_answer_score,
        tu.displayname as owner_displayname,
        tu.reputation as owner_reputation,
        tu.location_norm as owner_location,
        tu.posts_count as owner_posts_count,
        tu.avg_quality_score as owner_avg_quality,
        tu.p90_quality as owner_p90_quality,
        tu.high_quality_posts as owner_high_quality_posts,
        tu.avg_posts_per_month,
        tu.sd_posts_per_month,
        tu.total_badges,
        rank() over (order by pq.quality_score desc nulls last, qe.viewcount desc nulls last) as post_rank
    from question_enrichment qe
    join post_quality_score pq on pq.post_id = qe.post_id
    left join top_user_candidates tu on tu.user_id = (select owneruserid from posts p where p.id = qe.post_id)
    where coalesce(qe.viewcount, 0) > 0
)
select
    f.*,
    case
        when f.engagement_quality >= 15 and f.owner_avg_quality >= 10 then 'S-Tier'
        when f.engagement_quality >= 10 then 'A-Tier'
        when f.engagement_quality >= 5 then 'B-Tier'
        when f.engagement_quality >= 0 then 'C-Tier'
        else 'D-Tier'
    end as quality_bucket
from final f
where (f.top_tag_by_views is null or f.top_tag_by_views <> 'discussion')
  and (f.top_tag_by_score is null or f.top_tag_by_score not like '%homework%')
  and (f.owner_location is distinct from 'Unknown' or f.owner_reputation >= 1000)
order by f.post_rank
limit 250;