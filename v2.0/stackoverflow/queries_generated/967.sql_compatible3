with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        u.websiteurl,
        coalesce(nullif(trim(u.displayname), ''), ('user-' || cast(u.id as varchar))) as normalized_name,
        row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= (
        select coalesce(max(creationdate), date '1970-01-01') - interval '365 day'
        from users
    )
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        count(*) filter (where p.posttypeid not in (1,2) or p.posttypeid is null) as other_count,
        sum(coalesce(p.score,0)) as total_post_score,
        sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as total_question_views,
        avg(nullif(p.commentcount,0)) as avg_comment_count,
        max(p.creationdate) as last_post_date
    from posts p
    group by p.owneruserid
),
comment_activity as (
    select
        c.userid as user_id,
        count(*) as c_count,
        sum(coalesce(c.score,0)) as c_score,
        max(c.creationdate) as last_comment_date
    from comments c
    group by c.userid
),
vote_activity as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid not in (2,3) or v.votetypeid is null) as other_votes_cast,
        max(v.creationdate) as last_vote_date
    from votes v
    group by v.userid
),
badge_activity as (
    select
        b.userid as user_id,
        count(*) as badge_count,
        count(*) filter (where b.class = 1) as gold_count,
        count(*) filter (where b.class = 2) as silver_count,
        count(*) filter (where b.class = 3) as bronze_count,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_quality as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1 and p.acceptedanswerid is not null) as accepted_q,
        count(*) filter (where p.posttypeid = 1 and p.closeddate is not null) as closed_q,
        avg(nullif(p.favoritecount,0)) as avg_faves,
        percentile_cont(0.5) within group (order by coalesce(p.viewcount,0)) as median_q_views
    from posts p
    where p.posttypeid = 1
    group by p.owneruserid
),
answer_quality as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 2 and p.score >= 1) as positive_a,
        count(*) filter (where p.posttypeid = 2 and p.score <= -1) as negative_a,
        avg(coalesce(p.score,0)) filter (where p.posttypeid = 2) as avg_a_score
    from posts p
    where p.posttypeid = 2
    group by p.owneruserid
),
linking as (
    select
        p.owneruserid as user_id,
        count(distinct pl.id) filter (where pl.linktypeid = 1) as linked_out,
        count(distinct pl.id) filter (where pl.linktypeid = 3) as duplicates_marked,
        count(distinct case when pl.linktypeid = 3 and p.posttypeid = 1 then pl.id end) as q_marked_duplicate
    from posts p
    left join postlinks pl on pl.postid = p.id
    group by p.owneruserid
),
post_edits as (
    select
        ph.userid as user_id,
        count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edits_made,
        count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20)) as mod_events,
        count(*) filter (where ph.posthistorytypeid in (35,36)) as migrations
    from posthistory ph
    group by ph.userid
),
tag_usage as (
    select
        p.owneruserid as user_id,
        sum(array_length(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><'), 1)) as tag_tokens,
        count(*) filter (
            where p.posttypeid = 1
              and exists (
                  select 1
                  from tags t
                  where t.tagname = any(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><'))
                    and coalesce(t.isrequired,false) = true
              )
        ) as required_tag_questions
    from posts p
    where p.tags is not null
    group by p.owneruserid
),
user_last_activity as (
    select
        u.id as user_id,
        greatest(
            coalesce(ua.last_post_date, timestamp '1970-01-01'),
            coalesce(ca.last_comment_date, timestamp '1970-01-01'),
            coalesce(va.last_vote_date, timestamp '1970-01-01'),
            coalesce(ba.last_badge_date, timestamp '1970-01-01')
        ) as last_any_activity
    from users u
    left join user_activity ua on ua.user_id = u.id
    left join comment_activity ca on ca.user_id = u.id
    left join vote_activity va on va.user_id = u.id
    left join badge_activity ba on ba.user_id = u.id
),
ranked_users as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.location,
        ru.websiteurl,
        ru.normalized_name,
        ru.rn,
        ua.q_count,
        ua.a_count,
        ua.other_count,
        ua.total_post_score,
        ua.total_question_views,
        ua.avg_comment_count,
        ca.c_count,
        ca.c_score,
        va.upvotes_cast,
        va.downvotes_cast,
        va.other_votes_cast,
        ba.badge_count,
        ba.gold_count,
        ba.silver_count,
        ba.bronze_count,
        qq.accepted_q,
        qq.closed_q,
        qq.avg_faves,
        qq.median_q_views,
        aq.positive_a,
        aq.negative_a,
        aq.avg_a_score,
        lk.linked_out,
        lk.duplicates_marked,
        lk.q_marked_duplicate,
        pe.edits_made,
        pe.mod_events,
        pe.migrations,
        tu.tag_tokens,
        tu.required_tag_questions,
        ula.last_any_activity
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join comment_activity ca on ca.user_id = ru.user_id
    left join vote_activity va on va.user_id = ru.user_id
    left join badge_activity ba on ba.user_id = ru.user_id
    left join question_quality qq on qq.user_id = ru.user_id
    left join answer_quality aq on aq.user_id = ru.user_id
    left join linking lk on lk.user_id = ru.user_id
    left join post_edits pe on pe.user_id = ru.user_id
    left join tag_usage tu on tu.user_id = ru.user_id
    left join user_last_activity ula on ula.user_id = ru.user_id
),
score_components as (
    select
        r.user_id,
        r.displayname,
        r.reputation,
        r.creationdate,
        r.location,
        r.websiteurl,
        r.normalized_name,
        r.rn,
        r.q_count,
        r.a_count,
        r.other_count,
        r.total_post_score,
        r.total_question_views,
        r.avg_comment_count,
        r.c_count,
        r.c_score,
        r.upvotes_cast,
        r.downvotes_cast,
        r.other_votes_cast,
        r.badge_count,
        r.gold_count,
        r.silver_count,
        r.bronze_count,
        r.accepted_q,
        r.closed_q,
        r.avg_faves,
        r.median_q_views,
        r.positive_a,
        r.negative_a,
        r.avg_a_score,
        r.linked_out,
        r.duplicates_marked,
        r.q_marked_duplicate,
        r.edits_made,
        r.mod_events,
        r.migrations,
        r.tag_tokens,
        r.required_tag_questions,
        r.last_any_activity,
        coalesce(r.q_count,0) * 2
        + coalesce(r.a_count,0) * 3
        + coalesce(r.total_post_score,0) * 1
        + coalesce(r.upvotes_cast,0) * 0.2
        - coalesce(r.downvotes_cast,0) * 0.1
        + coalesce(r.badge_count,0) * 0.5
        + coalesce(r.accepted_q,0) * 1.5
        - coalesce(r.closed_q,0) * 1.0
        + coalesce(r.positive_a,0) * 0.7
        - coalesce(r.negative_a,0) * 0.5
        + coalesce(r.edits_made,0) * 0.3
        + coalesce(r.migrations,0) * 0.2
        + least(coalesce(r.tag_tokens,0), 200) * 0.05
        as activity_score,
        case
            when coalesce(r.a_count,0) > 0 then cast(coalesce(r.positive_a,0) as numeric) / nullif(r.a_count,0)
            else null
        end as pos_answer_ratio,
        case
            when coalesce(r.q_count,0) > 0 then cast(coalesce(r.accepted_q,0) as numeric) / nullif(r.q_count,0)
            else null
        end as q_accept_ratio
    from ranked_users r
),
banded as (
    select
        s.user_id,
        s.displayname,
        s.reputation,
        s.creationdate,
        s.location,
        s.websiteurl,
        s.normalized_name,
        s.rn,
        s.q_count,
        s.a_count,
        s.other_count,
        s.total_post_score,
        s.total_question_views,
        s.avg_comment_count,
        s.c_count,
        s.c_score,
        s.upvotes_cast,
        s.downvotes_cast,
        s.other_votes_cast,
        s.badge_count,
        s.gold_count,
        s.silver_count,
        s.bronze_count,
        s.accepted_q,
        s.closed_q,
        s.avg_faves,
        s.median_q_views,
        s.positive_a,
        s.negative_a,
        s.avg_a_score,
        s.linked_out,
        s.duplicates_marked,
        s.q_marked_duplicate,
        s.edits_made,
        s.mod_events,
        s.migrations,
        s.tag_tokens,
        s.required_tag_questions,
        s.last_any_activity,
        s.activity_score,
        s.pos_answer_ratio,
        s.q_accept_ratio,
        least(greatest(floor(coalesce(s.activity_score,0) * 10.0 / 200.0)::int, 0), 9) + 1 as activity_bucket,
        row_number() over (order by coalesce(s.activity_score, -1e9) desc, coalesce(s.reputation, -1) desc, s.user_id) as global_rank,
        dense_rank() over (partition by coalesce(s.location,'Unknown') order by coalesce(s.activity_score, -1e9) desc) as location_rank,
        rank() over (order by coalesce(s.q_accept_ratio, -1.0) desc) as q_accept_rank,
        rank() over (order by coalesce(s.pos_answer_ratio, -1.0) desc) as a_quality_rank
    from score_components s
),
final as (
    select
        b.user_id,
        b.displayname,
        b.reputation,
        b.creationdate,
        b.location,
        b.websiteurl,
        b.normalized_name,
        b.q_count,
        b.a_count,
        b.other_count,
        b.total_post_score,
        b.total_question_views,
        round(coalesce(b.avg_comment_count,0), 2) as avg_comment_count,
        b.c_count,
        b.c_score,
        b.upvotes_cast,
        b.downvotes_cast,
        b.other_votes_cast,
        b.badge_count,
        b.gold_count,
        b.silver_count,
        b.bronze_count,
        b.accepted_q,
        b.closed_q,
        round(coalesce(b.avg_faves,0), 2) as avg_faves,
        b.median_q_views,
        b.positive_a,
        b.negative_a,
        round(coalesce(b.avg_a_score,0), 2) as avg_a_score,
        b.linked_out,
        b.duplicates_marked,
        b.q_marked_duplicate,
        b.edits_made,
        b.mod_events,
        b.migrations,
        b.tag_tokens,
        b.required_tag_questions,
        b.last_any_activity,
        round(coalesce(b.activity_score,0), 2) as activity_score,
        round(coalesce(b.pos_answer_ratio,0), 4) as pos_answer_ratio,
        round(coalesce(b.q_accept_ratio,0), 4) as q_accept_ratio,
        b.activity_bucket,
        b.global_rank,
        b.location_rank,
        b.q_accept_rank,
        b.a_quality_rank,
        case
            when b.activity_bucket >= 9 then 'Tier S'
            when b.activity_bucket >= 7 then 'Tier A'
            when b.activity_bucket >= 5 then 'Tier B'
            when b.activity_bucket >= 3 then 'Tier C'
            when b.activity_bucket >= 1 then 'Tier D'
            else 'Tier E'
        end as activity_tier,
        case
            when b.last_any_activity is null then 'Dormant'
            when b.last_any_activity >= timestamp '2024-10-01 12:34:56' - interval '30 day' then 'Active-30'
            when b.last_any_activity >= timestamp '2024-10-01 12:34:56' - interval '90 day' then 'Active-90'
            when b.last_any_activity >= timestamp '2024-10-01 12:34:56' - interval '180 day' then 'Active-180'
            else 'Inactive'
        end as recency_bucket
    from banded b
)
select *
from final f
where
    (
        f.activity_bucket >= 5
        or (f.q_accept_ratio is not null and f.q_accept_ratio >= 0.25)
        or (f.pos_answer_ratio is not null and f.pos_answer_ratio >= 0.5)
    )
    and coalesce(f.location, '') not ilike '%test%'
    and (f.websiteurl is null or f.websiteurl not ilike '%spam%')
    and (
        f.reputation >= (
            select percentile_disc(0.5) within group (order by reputation)
            from users
        )
        or f.badge_count >= (
            select coalesce(max(b2.badge_count),0) / 10
            from badge_activity b2
        )
    )
order by
    f.global_rank
fetch first 250 rows only;