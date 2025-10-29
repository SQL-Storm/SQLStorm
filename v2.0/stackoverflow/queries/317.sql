with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown') as domain,
           row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
),
top_recent as (
    select *
    from recent_users
    where rn <= 5000
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(case when p.posttypeid = 1 then 1 end) as q_count,
        count(case when p.posttypeid = 2 then 1 end) as a_count,
        sum(coalesce(p.score,0)) as post_score_sum,
        sum(coalesce(p.viewcount,0)) as view_sum,
        max(p.creationdate) as last_post_date
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
comment_stats as (
    select
        c.userid as user_id,
        count(*) as comment_count,
        sum(coalesce(c.score,0)) as comment_score_sum,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
vote_agg as (
    select
        v.userid as user_id,
        count(case when v.votetypeid = 2 then 1 end) as upvotes_cast,
        count(case when v.votetypeid = 3 then 1 end) as downvotes_cast,
        count(case when v.votetypeid = 5 then 1 end) as favorites_cast,
        count(case when v.votetypeid = 8 then 1 end) as bounties_started,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_amount_total,
        max(v.creationdate) as last_vote_date
    from votes v
    where v.userid is not null
    group by v.userid
),
badge_agg as (
    select
        b.userid as user_id,
        count(*) as badge_count,
        count(case when b.class = 1 then 1 end) as gold_count,
        count(case when b.class = 2 then 1 end) as silver_count,
        count(case when b.class = 3 then 1 end) as bronze_count,
        count(case when b.tagbased = true then 1 end) as tag_badge_count,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_metrics as (
    select
        q.owneruserid as user_id,
        count(*) as questions_total,
        avg(nullif(q.answercount,0)) as avg_answers_when_any,
        sum(case when q.acceptedanswerid is not null then 1 else 0 end) as accepted_questions,
        count(case when q.closeddate is not null then 1 end) as closed_questions,
        avg(q.score) as avg_q_score,
        sum(coalesce(q.favoritecount,0)) as fav_sum
    from posts q
    where q.posttypeid = 1
      and q.owneruserid is not null
    group by q.owneruserid
),
answer_metrics as (
    select
        a.owneruserid as user_id,
        count(*) as answers_total,
        sum(case when a.id = q.acceptedanswerid then 1 else 0 end) as accepted_answers,
        avg(a.score) as avg_a_score
    from posts a
    left join posts q on q.id = a.parentid and q.posttypeid = 1
    where a.posttypeid = 2
      and a.owneruserid is not null
    group by a.owneruserid
),
postlink_dupes as (
    select
        p.owneruserid as user_id,
        count(case when pl.linktypeid = 3 then 1 end) as duplicate_links_out,
        count(case when r.owneruserid is not null and pl.linktypeid = 3 then 1 end) as duplicate_links_out_to_users,
        count(case when pl.linktypeid = 1 then 1 end) as links_out
    from posts p
    left join postlinks pl on pl.postid = p.id
    left join posts r on r.id = pl.relatedpostid
    where p.owneruserid is not null
    group by p.owneruserid
),
edits_cte as (
    select
        ph.userid as user_id,
        count(case when ph.posthistorytypeid in (4,5,6,7,8,9,24) then 1 end) as edits_made,
        count(case when ph.posthistorytypeid in (10) then 1 end) as closes_cast_legacy,
        count(case when ph.posthistorytypeid in (11) then 1 end) as reopens_cast_legacy,
        count(case when ph.posthistorytypeid in (33) then 1 end) as notices_added,
        count(case when ph.posthistorytypeid in (34) then 1 end) as notices_removed,
        max(ph.creationdate) as last_edit_event
    from posthistory ph
    where ph.userid is not null
    group by ph.userid
),
tag_usage as (
    select
        p.owneruserid as user_id,
        unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tagname
    from posts p
    where p.posttypeid = 1
      and p.tags is not null
      and p.owneruserid is not null
),
top_tags as (
    select
        tu.user_id,
        t.tagname,
        count(*) as tag_count,
        row_number() over (partition by tu.user_id order by count(*) desc, t.tagname) as tag_rank
    from tag_usage tu
    join tags t on lower(t.tagname) = lower(tu.tagname)
    group by tu.user_id, t.tagname
),
user_top3_tags as (
    select user_id,
           string_agg(tagname || ':' || cast(tag_count as varchar), ', ' order by tag_rank) filter (where tag_rank <= 3) as top3_tags
    from top_tags
    group by user_id
),
post_recency as (
    select
        p.owneruserid as user_id,
        percentile_cont(0.5) within group (order by extract(epoch from (timestamp '2024-10-01 12:34:56' - p.creationdate)) / 86400.0) as p50_post_age_days,
        percentile_cont(0.9) within group (order by extract(epoch from (timestamp '2024-10-01 12:34:56' - p.creationdate)) / 86400.0) as p90_post_age_days
    from posts p
    where p.owneruserid is not null
      and p.creationdate is not null
    group by p.owneruserid
),
user_last_activity as (
    select
        u.id as user_id,
        greatest(
            coalesce(ua.last_post_date, timestamp '1970-01-01 00:00:00'),
            coalesce(cs.last_comment_date, timestamp '1970-01-01 00:00:00'),
            coalesce(va.last_vote_date, timestamp '1970-01-01 00:00:00'),
            coalesce(ba.last_badge_date, timestamp '1970-01-01 00:00:00'),
            coalesce(ed.last_edit_event, timestamp '1970-01-01 00:00:00'),
            u.lastaccessdate
        ) as last_activity
    from users u
    left join user_activity ua on ua.user_id = u.id
    left join comment_stats cs on cs.user_id = u.id
    left join vote_agg va on va.user_id = u.id
    left join badge_agg ba on ba.user_id = u.id
    left join edits_cte ed on ed.user_id = u.id
),
activity_rank as (
    select
        tr.user_id,
        dense_rank() over (order by coalesce(ua.post_score_sum,0) + coalesce(cs.comment_score_sum,0) + coalesce(va.upvotes_cast,0) - coalesce(va.downvotes_cast,0) desc) as score_rank,
        dense_rank() over (order by coalesce(ua.q_count,0) + coalesce(ua.a_count,0) desc) as volume_rank,
        dense_rank() over (order by coalesce(ba.badge_count,0) desc) as badge_rank
    from top_recent tr
    left join user_activity ua on ua.user_id = tr.user_id
    left join comment_stats cs on cs.user_id = tr.user_id
    left join vote_agg va on va.user_id = tr.user_id
    left join badge_agg ba on ba.user_id = tr.user_id
),
null_edge as (
    select u.id as user_id,
           case when u.displayname is null or u.displayname = '' then 1 else 0 end as is_anon_name,
           case when u.websiteurl is null then 1 else 0 end as no_website,
           case when u.location is null then 1 else 0 end as no_location
    from users u
)
select
    tr.user_id,
    tr.displayname,
    tr.reputation,
    tr.creationdate as user_created,
    tr.location,
    tr.domain as website_domain,
    coalesce(ua.q_count,0) as question_count,
    coalesce(ua.a_count,0) as answer_count,
    coalesce(ua.post_score_sum,0) as post_score_sum,
    coalesce(ua.view_sum,0) as total_views,
    cs.comment_count,
    cs.comment_score_sum,
    va.upvotes_cast,
    va.downvotes_cast,
    va.favorites_cast,
    va.bounties_started,
    va.bounty_amount_total,
    ba.badge_count,
    ba.gold_count,
    ba.silver_count,
    ba.bronze_count,
    ba.tag_badge_count,
    qm.questions_total,
    qm.accepted_questions,
    qm.closed_questions,
    round(coalesce(qm.avg_q_score,0), 2) as avg_q_score,
    round(coalesce(am.avg_a_score,0), 2) as avg_a_score,
    am.answers_total,
    am.accepted_answers,
    pd.duplicate_links_out,
    pd.duplicate_links_out_to_users,
    pd.links_out,
    ut.top3_tags,
    pr.p50_post_age_days,
    pr.p90_post_age_days,
    ula.last_activity,
    ar.score_rank,
    ar.volume_rank,
    ar.badge_rank,
    case
        when coalesce(ua.q_count,0) + coalesce(ua.a_count,0) = 0 then 'inactive'
        when coalesce(ua.a_count,0) > coalesce(ua.q_count,0) * 2 then 'answerer'
        when coalesce(ua.q_count,0) > coalesce(ua.a_count,0) * 2 then 'questioner'
        else 'balanced'
    end as contributor_profile,
    case when ne.is_anon_name = 1 and ne.no_website = 1 and ne.no_location = 1 then 'minimal_profile' else 'detailed_profile' end as profile_completeness,
    coalesce(ua.last_post_date, timestamp '1970-01-01 00:00:00') as last_post_date,
    coalesce(cs.last_comment_date, timestamp '1970-01-01 00:00:00') as last_comment_date,
    coalesce(va.last_vote_date, timestamp '1970-01-01 00:00:00') as last_vote_date,
    coalesce(ba.last_badge_date, timestamp '1970-01-01 00:00:00') as last_badge_date,
    coalesce(ed.last_edit_event, timestamp '1970-01-01 00:00:00') as last_edit_event,
    case
        when (coalesce(ua.view_sum,0) > 100000 and coalesce(ua.post_score_sum,0) > 1000)
          or (coalesce(qm.accepted_questions,0) + coalesce(am.accepted_answers,0)) >= 50
        then 1 else 0
    end as power_user_flag
from top_recent tr
left join user_activity ua on ua.user_id = tr.user_id
left join comment_stats cs on cs.user_id = tr.user_id
left join vote_agg va on va.user_id = tr.user_id
left join badge_agg ba on ba.user_id = tr.user_id
left join question_metrics qm on qm.user_id = tr.user_id
left join answer_metrics am on am.user_id = tr.user_id
left join postlink_dupes pd on pd.user_id = tr.user_id
left join user_top3_tags ut on ut.user_id = tr.user_id
left join post_recency pr on pr.user_id = tr.user_id
left join user_last_activity ula on ula.user_id = tr.user_id
left join activity_rank ar on ar.user_id = tr.user_id
left join edits_cte ed on ed.user_id = tr.user_id
left join null_edge ne on ne.user_id = tr.user_id
where
    (
        coalesce(ua.q_count,0) + coalesce(ua.a_count,0) + coalesce(cs.comment_count,0)
        + coalesce(va.upvotes_cast,0) + coalesce(ba.badge_count,0)
    ) > 0
    and (
        tr.domain not like '%example.%'
        or tr.domain is null
    )
    and (
        tr.reputation > 0
        or (coalesce(ua.post_score_sum,0) + coalesce(cs.comment_score_sum,0)) > 0
    )
order by
    power_user_flag desc,
    ar.score_rank,
    coalesce(ua.post_score_sum,0) desc,
    tr.reputation desc,
    tr.user_id
limit 500;