-- {"query": "307.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3486} 
with recent_users as (
    select
        u.id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        u.websiteurl,
        coalesce(nullif(trim(u.location), ''), 'Unknown') as norm_location,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= now() - interval '5 years'
),
post_activity as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.commentcount,
        p.favoritecount,
        p.closeddate,
        p.tags,
        case when p.posttypeid = 1 then 1 else 0 end as is_question,
        case when p.posttypeid = 2 then 1 else 0 end as is_answer
    from posts p
    where p.creationdate >= (select min(creationdate) from recent_users)
),
user_posts as (
    select
        ru.id as user_id,
        count(*) filter (where pa.is_question = 1) as questions,
        count(*) filter (where pa.is_answer = 1) as answers,
        coalesce(sum(pa.score),0) as total_post_score,
        avg(nullif(pa.score,0)) as avg_nonzero_post_score,
        max(pa.viewcount) as max_views,
        sum(case when pa.closeddate is not null then 1 else 0 end) as closed_posts,
        sum(pa.commentcount) as total_comments_on_posts
    from recent_users ru
    left join post_activity pa
      on pa.user_id = ru.id
    group by ru.id
),
tag_explode as (
    select
        pa.user_id,
        unnest(string_to_array(substring(pa.tags, 2, greatest(length(pa.tags)-2,0)), '><')) as tagname
    from post_activity pa
    where pa.is_question = 1
      and pa.tags is not null
),
top_user_tags as (
    select
        te.user_id,
        te.tagname,
        count(*) as tag_q_count,
        row_number() over (partition by te.user_id order by count(*) desc, te.tagname) as rn
    from tag_explode te
    group by te.user_id, te.tagname
),
votes_agg as (
    select
        v.postid,
        v.userid,
        count(*) filter (where v.votetypeid = 2) as upvotes_given_on_posts,
        count(*) filter (where v.votetypeid = 3) as downvotes_given_on_posts,
        count(*) filter (where v.votetypeid = 5) as favorites_given,
        count(*) filter (where v.votetypeid = 1) as accepts_cast
    from votes v
    where v.creationdate >= now() - interval '5 years'
    group by v.postid, v.userid
),
user_votes as (
    select
        ru.id as user_id,
        coalesce(sum(va.upvotes_given_on_posts),0) as upvotes_given,
        coalesce(sum(va.downvotes_given_on_posts),0) as downvotes_given,
        coalesce(sum(va.favorites_given),0) as favorites_given,
        coalesce(sum(va.accepts_cast),0) as accepts_cast
    from recent_users ru
    left join votes_agg va
      on va.userid = ru.id
    group by ru.id
),
received_votes as (
    select
        pa.user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_received,
        count(*) filter (where v.votetypeid = 3) as downvotes_received,
        sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_total
    from post_activity pa
    left join votes v
      on v.postid = pa.post_id
    group by pa.user_id
),
badges_agg as (
    select
        b.userid as user_id,
        count(*) as total_badges,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where b.tagbased = 1) as tag_badges
    from badges b
    where b.date >= now() - interval '5 years'
    group by b.userid
),
edits_agg as (
    select
        ph.userid as user_id,
        count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits_made,
        count(*) filter (where ph.posthistorytypeid in (24)) as suggested_edits_applied,
        count(*) filter (where ph.posthistorytypeid in (10)) as closes_cast_in_history
    from posthistory ph
    where ph.creationdate >= now() - interval '5 years'
    group by ph.userid
),
links_agg as (
    select
        p.owneruserid as user_id,
        count(*) filter (where pl.linktypeid = 1) as links_linked,
        count(*) filter (where pl.linktypeid = 3 and p.posttypeid = 1) as dup_marks_on_questions,
        count(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) as distinct_dupe_targets
    from postlinks pl
    join posts p on p.id = pl.postid
    group by p.owneruserid
),
comment_stats as (
    select
        c.userid as user_id,
        count(*) as comments_made,
        avg(c.score) as avg_comment_score,
        max(c.score) as max_comment_score,
        sum(case when c.text ilike '%thanks%' or c.text ilike '%thank you%' then 1 else 0 end) as thankyous
    from comments c
    where c.creationdate >= now() - interval '5 years'
    group by c.userid
),
user_activity_window as (
    select
        pa.user_id,
        date_trunc('month', pa.creationdate) as month_bucket,
        count(*) as posts_in_month,
        sum(pa.score) as score_in_month,
        dense_rank() over (partition by pa.user_id order by date_trunc('month', pa.creationdate)) as month_seq
    from post_activity pa
    group by pa.user_id, date_trunc('month', pa.creationdate)
),
growth_metrics as (
    select
        uaw.user_id,
        sum(uaw.posts_in_month) as total_posts_windowed,
        avg(uaw.posts_in_month) as avg_posts_per_active_month,
        stddev_pop(uaw.posts_in_month) as stdev_posts_per_active_month,
        corr(uaw.month_seq::numeric, uaw.posts_in_month::numeric) as trend_posts_per_month
    from user_activity_window uaw
    group by uaw.user_id
),
activity_rank as (
    select
        ru.id as user_id,
        rank() over (order by coalesce(up.total_post_score,0) desc, coalesce(rv.upvotes_received,0) desc) as rank_by_score,
        percent_rank() over (order by coalesce(up.questions + up.answers,0)) as pct_by_postcount
    from recent_users ru
    left join user_posts up on up.user_id = ru.id
    left join received_votes rv on rv.user_id = ru.id
),
post_type_mix as (
    select
        ru.id as user_id,
        case
            when coalesce(up.questions,0) + coalesce(up.answers,0) = 0 then null
            else round(100.0 * coalesce(up.questions,0) / nullif(coalesce(up.questions,0) + coalesce(up.answers,0),0), 2)
        end as pct_questions
    from recent_users ru
    left join user_posts up on up.user_id = ru.id
),
null_sentinel as (
    select
        ru.id as user_id,
        case when ru.websiteurl is null or trim(ru.websiteurl) = '' then 1 else 0 end as missing_website,
        case when ru.location is null or trim(ru.location) = '' then 1 else 0 end as missing_location
    from recent_users ru
),
correlated_quality as (
    select
        ru.id as user_id,
        (
            select avg(p2.score)
            from posts p2
            where p2.owneruserid = ru.id
              and p2.posttypeid in (1,2)
              and p2.creationdate >= ru.creationdate
        ) as avg_score_since_signup,
        (
            select count(*)
            from posts p3
            where p3.owneruserid = ru.id
              and p3.posttypeid = 1
              and p3.closeddate is not null
        ) as closed_questions_total
    from recent_users ru
),
dupe_clusters as (
    select
        pa.user_id,
        count(*) filter (where pl.linktypeid = 3) as dupe_edges,
        count(distinct case when pl.linktypeid = 3 then least(pl.postid, pl.relatedpostid) || '-' || greatest(pl.postid, pl.relatedpostid) end) as dupe_pairs
    from post_activity pa
    left join postlinks pl on pl.postid = pa.post_id
    group by pa.user_id
),
final as (
    select
        ru.id as user_id,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        ru.norm_location,
        coalesce(up.questions,0) as questions,
        coalesce(up.answers,0) as answers,
        coalesce(up.total_post_score,0) as total_post_score,
        up.avg_nonzero_post_score,
        up.max_views,
        up.closed_posts,
        up.total_comments_on_posts,
        coalesce(rv.upvotes_received,0) as upvotes_received,
        coalesce(rv.downvotes_received,0) as downvotes_received,
        coalesce(rv.bounty_total,0) as bounty_total,
        coalesce(uv.upvotes_given,0) as upvotes_given,
        coalesce(uv.downvotes_given,0) as downvotes_given,
        coalesce(uv.favorites_given,0) as favorites_given,
        coalesce(uv.accepts_cast,0) as accepts_cast,
        coalesce(ba.total_badges,0) as total_badges,
        coalesce(ba.gold_badges,0) as gold_badges,
        coalesce(ba.silver_badges,0) as silver_badges,
        coalesce(ba.bronze_badges,0) as bronze_badges,
        coalesce(ba.tag_badges,0) as tag_badges,
        coalesce(ea.edits_made,0) as edits_made,
        coalesce(ea.suggested_edits_applied,0) as suggested_edits_applied,
        coalesce(ea.closes_cast_in_history,0) as closes_cast_in_history,
        coalesce(la.links_linked,0) as links_linked,
        coalesce(la.dup_marks_on_questions,0) as dup_marks_on_questions,
        coalesce(la.distinct_dupe_targets,0) as distinct_dupe_targets,
        coalesce(cs.comments_made,0) as comments_made,
        cs.avg_comment_score,
        cs.max_comment_score,
        coalesce(cs.thankyous,0) as thankyous_in_comments,
        gm.total_posts_windowed,
        gm.avg_posts_per_active_month,
        gm.stdev_posts_per_active_month,
        gm.trend_posts_per_month,
        ar.rank_by_score,
        ar.pct_by_postcount,
        ptm.pct_questions,
        case when ns.missing_website = 1 then 'NoSite' else 'HasSite' end as website_flag,
        case when ns.missing_location = 1 then 'NoLoc' else 'HasLoc' end as location_flag,
        cq.avg_score_since_signup,
        cq.closed_questions_total,
        coalesce(dc.dupe_edges,0) as dupe_edges,
        coalesce(dc.dupe_pairs,0) as dupe_pairs,
        tut.tagname as top_tag,
        tut.tag_q_count as top_tag_q_count
    from recent_users ru
    left join user_posts up on up.user_id = ru.id
    left join user_votes uv on uv.user_id = ru.id
    left join received_votes rv on rv.user_id = ru.id
    left join badges_agg ba on ba.user_id = ru.id
    left join edits_agg ea on ea.user_id = ru.id
    left join links_agg la on la.user_id = ru.id
    left join comment_stats cs on cs.user_id = ru.id
    left join growth_metrics gm on gm.user_id = ru.id
    left join activity_rank ar on ar.user_id = ru.id
    left join post_type_mix ptm on ptm.user_id = ru.id
    left join null_sentinel ns on ns.user_id = ru.id
    left join correlated_quality cq on cq.user_id = ru.id
    left join dupe_clusters dc on dc.user_id = ru.id
    left join top_user_tags tut on tut.user_id = ru.id and tut.rn = 1
),
score_buckets as (
    select
        f.*,
        case
            when coalesce(f.total_post_score,0) >= 1000 then 'A: 1000+'
            when coalesce(f.total_post_score,0) >= 100 then 'B: 100-999'
            when coalesce(f.total_post_score,0) >= 10 then 'C: 10-99'
            when coalesce(f.total_post_score,0) > 0 then 'D: 1-9'
            when coalesce(f.total_post_score,0) = 0 then 'E: 0'
            else 'F: Negative'
        end as score_bucket
    from final f
),
ranked as (
    select
        sb.*,
        row_number() over (
            partition by sb.score_bucket
            order by
                coalesce(sb.total_post_score,0) desc,
                coalesce(sb.upvotes_received,0) desc,
                coalesce(sb.reputation,0) desc,
                sb.user_id
        ) as bucket_rank
    from score_buckets sb
)
select
    r.user_id,
    r.displayname,
    r.reputation,
    r.cohort_month,
    r.norm_location,
    r.questions,
    r.answers,
    r.total_post_score,
    r.avg_nonzero_post_score,
    r.max_views,
    r.closed_posts,
    r.total_comments_on_posts,
    r.upvotes_received,
    r.downvotes_received,
    r.bounty_total,
    r.upvotes_given,
    r.downvotes_given,
    r.favorites_given,
    r.accepts_cast,
    r.total_badges,
    r.gold_badges,
    r.silver_badges,
    r.bronze_badges,
    r.tag_badges,
    r.edits_made,
    r.suggested_edits_applied,
    r.closes_cast_in_history,
    r.links_linked,
    r.dup_marks_on_questions,
    r.distinct_dupe_targets,
    r.comments_made,
    r.avg_comment_score,
    r.max_comment_score,
    r.thankyous_in_comments,
    r.total_posts_windowed,
    r.avg_posts_per_active_month,
    r.stdev_posts_per_active_month,
    r.trend_posts_per_month,
    r.rank_by_score,
    r.pct_by_postcount,
    r.pct_questions,
    r.website_flag,
    r.location_flag,
    r.avg_score_since_signup,
    r.closed_questions_total,
    r.dupe_edges,
    r.dupe_pairs,
    r.top_tag,
    r.top_tag_q_count,
    r.score_bucket,
    r.bucket_rank
from ranked r
where
    (
        r.rank_by_score <= 100
        or r.bucket_rank <= 50
        or (r.avg_posts_per_active_month is not null and r.avg_posts_per_active_month > 2)
    )
order by
    r.score_bucket,
    r.bucket_rank,
    r.rank_by_score nulls last,
    r.user_id;