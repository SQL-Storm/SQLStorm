with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        count(b.id) as total_badges,
        max(b.date) as last_badge_date
    from users u
    left join badges b
      on b.userid = u.id
     and b.date >= u.creationdate
    where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '18 months' from users)
    group by u.id, u.displayname, u.reputation, u.creationdate, u.location, coalesce(nullif(trim(u.websiteurl), ''), 'n/a')
),
q_and_a as (
    select
        p.owneruserid as user_id,
        sum(case when p.posttypeid = 1 then 1 else 0 end) as questions,
        sum(case when p.posttypeid = 2 then 1 else 0 end) as answers,
        sum(case when p.posttypeid = 1 then coalesce(p.viewcount, 0) else 0 end) as question_views,
        sum(coalesce(p.score, 0)) as total_post_score,
        count(*) as total_posts,
        max(p.lastactivitydate) as last_activity
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= (select date_trunc('month', max(creationdate)) - interval '18 months' from posts)
    group by p.owneruserid
),
accepted_answers as (
    select
        a.owneruserid as user_id,
        count(*) as accepted_answers
    from posts q
    join posts a
      on a.id = q.acceptedanswerid
     and a.posttypeid = 2
    where q.posttypeid = 1
      and a.owneruserid is not null
      and q.creationdate >= (select date_trunc('month', max(creationdate)) - interval '18 months' from posts)
    group by a.owneruserid
),
vote_agg as (
    select
        p.owneruserid as user_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_rcvd,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_rcvd,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount, 0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount, 0) else 0 end) as bounty_awarded
    from posts p
    left join votes v
      on v.postid = p.id
     and v.creationdate >= p.creationdate
    where p.owneruserid is not null
      and p.creationdate >= (select date_trunc('month', max(creationdate)) - interval '18 months' from posts)
    group by p.owneruserid
),
comment_stats as (
    select
        coalesce(c.userid, p.owneruserid) as user_id,
        count(*) filter (where c.userid is not null) as comments_by_user,
        count(*) filter (where c.userid is null) as comments_by_anon,
        sum(coalesce(c.score, 0)) as comment_score_sum
    from comments c
    left join posts p
      on p.id = c.postid
    where c.creationdate >= (select date_trunc('month', max(creationdate)) - interval '18 months' from comments)
    group by coalesce(c.userid, p.owneruserid)
),
tag_expertise as (
    select
        p.owneruserid as user_id,
        lower(t.tag_name) as tag_name,
        count(*) as tag_posts,
        sum(case when p.posttypeid = 2 then 1 else 0 end) as tag_answers,
        sum(case when p.posttypeid = 1 then 1 else 0 end) as tag_questions,
        sum(coalesce(p.score,0)) as tag_score
    from posts p,
         lateral (
           select unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag_name
         ) t
    where p.owneruserid is not null
      and p.tags is not null
      and p.posttypeid in (1,2)
      and p.creationdate >= (select date_trunc('month', max(creationdate)) - interval '18 months' from posts)
    group by p.owneruserid, lower(t.tag_name)
),
top_tag_per_user as (
    select user_id, tag_name, tag_posts, tag_answers, tag_questions, tag_score
    from (
        select
            te.*,
            row_number() over (partition by te.user_id order by te.tag_score desc, te.tag_answers desc, te.tag_posts desc, te.tag_name) as rn
        from tag_expertise te
    ) s
    where rn = 1
),
post_edits as (
    select
        ph.userid as editor_user_id,
        ph.postid,
        count(*) filter (where ph.posthistorytypeid in (4,5,6,24)) as edit_events,
        min(ph.creationdate) as first_edit_at,
        max(ph.creationdate) as last_edit_at,
        count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20)) as mod_events
    from posthistory ph
    where ph.creationdate >= (select date_trunc('month', max(creationdate)) - interval '18 months' from posthistory)
    group by ph.userid, ph.postid
),
dup_links as (
    select
        pl.postid,
        pl.relatedpostid,
        pl.creationdate,
        pl.linktypeid
    from postlinks pl
    where pl.linktypeid = 3
),
q_closures as (
    select
        ph.postid,
        min(ph.creationdate) as first_closed_at,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as reopened_at,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        max(case
            when ph.posthistorytypeid = 10 then
                nullif(regexp_replace(ph.comment, '[^0-9]', '', 'g'), '')
            else null
        end) as last_close_reason_code
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
user_activity as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.location,
        ru.websiteurl,
        ru.gold_badges,
        ru.silver_badges,
        ru.bronze_badges,
        ru.total_badges,
        qa.questions,
        qa.answers,
        qa.question_views,
        qa.total_post_score,
        qa.total_posts,
        qa.last_activity,
        aa.accepted_answers,
        va.upvotes_rcvd,
        va.downvotes_rcvd,
        va.bounty_started,
        va.bounty_awarded,
        cs.comments_by_user,
        cs.comments_by_anon,
        cs.comment_score_sum,
        tt.tag_name as top_tag,
        tt.tag_posts as top_tag_posts,
        tt.tag_answers as top_tag_answers,
        tt.tag_questions as top_tag_questions,
        tt.tag_score as top_tag_score
    from recent_users ru
    left join q_and_a qa on qa.user_id = ru.user_id
    left join accepted_answers aa on aa.user_id = ru.user_id
    left join vote_agg va on va.user_id = ru.user_id
    left join comment_stats cs on cs.user_id = ru.user_id
    left join top_tag_per_user tt on tt.user_id = ru.user_id
),
ranked as (
    select
        ua.user_id,
        ua.displayname,
        ua.reputation,
        ua.creationdate,
        ua.location,
        ua.websiteurl,
        ua.gold_badges,
        ua.silver_badges,
        ua.bronze_badges,
        ua.total_badges,
        ua.questions,
        ua.answers,
        ua.question_views,
        ua.total_post_score,
        ua.total_posts,
        ua.last_activity,
        ua.accepted_answers,
        ua.upvotes_rcvd,
        ua.downvotes_rcvd,
        ua.bounty_started,
        ua.bounty_awarded,
        ua.comments_by_user,
        ua.comments_by_anon,
        ua.comment_score_sum,
        ua.top_tag,
        ua.top_tag_posts,
        ua.top_tag_answers,
        ua.top_tag_questions,
        ua.top_tag_score,
        coalesce(ua.answers,0) + coalesce(ua.questions,0) as total_q_a,
        coalesce(ua.total_post_score,0) + coalesce(ua.comment_score_sum,0) as total_score_all,
        case when coalesce(ua.answers,0) > 0 then round(coalesce(ua.accepted_answers,0) / nullif(ua.answers,0), 4) else 0 end as accept_ratio,
        row_number() over (order by coalesce(ua.reputation,0) desc, coalesce(ua.total_post_score,0) desc, coalesce(ua.answers,0) desc) as rn_rep,
        dense_rank() over (order by coalesce(ua.total_post_score,0) + coalesce(ua.comment_score_sum,0) desc) as dr_score,
        ntile(10) over (order by coalesce(ua.answers,0) desc) as answers_decile,
        lag(ua.reputation) over (order by ua.reputation desc) as prev_rep,
        lead(ua.reputation) over (order by ua.reputation desc) as next_rep
    from user_activity ua
    group by
        ua.user_id,
        ua.displayname,
        ua.reputation,
        ua.creationdate,
        ua.location,
        ua.websiteurl,
        ua.gold_badges,
        ua.silver_badges,
        ua.bronze_badges,
        ua.total_badges,
        ua.questions,
        ua.answers,
        ua.question_views,
        ua.total_post_score,
        ua.total_posts,
        ua.last_activity,
        ua.accepted_answers,
        ua.upvotes_rcvd,
        ua.downvotes_rcvd,
        ua.bounty_started,
        ua.bounty_awarded,
        ua.comments_by_user,
        ua.comments_by_anon,
        ua.comment_score_sum,
        ua.top_tag,
        ua.top_tag_posts,
        ua.top_tag_answers,
        ua.top_tag_questions,
        ua.top_tag_score
),
post_samples as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        p.posttypeid,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        qc.first_closed_at,
        qc.reopened_at,
        qc.close_events,
        qc.last_close_reason_code,
        dl.relatedpostid as duplicate_of
    from posts p
    left join q_closures qc on qc.postid = p.id
    left join dup_links dl on dl.postid = p.id
    where p.owneruserid in (select user_id from ranked where rn_rep <= 500)
      and p.creationdate >= (select date_trunc('month', max(creationdate)) - interval '18 months' from posts)
),
metrics as (
    select
        r.user_id,
        count(ps.post_id) filter (where ps.posttypeid = 1) as sample_questions,
        count(ps.post_id) filter (where ps.posttypeid = 2) as sample_answers,
        avg(nullif(ps.score,0)) filter (where ps.posttypeid = 1) as avg_q_score_nonzero,
        avg(ps.viewcount) filter (where ps.posttypeid = 1) as avg_q_views,
        count(ps.post_id) filter (where ps.first_closed_at is not null) as closed_posts,
        count(ps.post_id) filter (where ps.duplicate_of is not null) as duplicate_marked,
        count(distinct ps.duplicate_of) as distinct_dupe_targets,
        max(ps.close_events) as max_close_events_on_post
    from ranked r
    left join post_samples ps on ps.user_id = r.user_id
    group by r.user_id
)
select
    r.user_id,
    coalesce(r.displayname, concat('user_', cast(r.user_id as varchar))) as displayname,
    r.reputation,
    r.prev_rep,
    r.next_rep,
    cast(r.creationdate as date) as joined_on,
    coalesce(nullif(trim(r.location), ''), 'Unknown') as location,
    r.websiteurl,
    concat(r.gold_badges, '/', r.silver_badges, '/', r.bronze_badges) as badge_breakdown,
    r.total_badges,
    r.questions,
    r.answers,
    r.total_q_a,
    r.accepted_answers,
    r.accept_ratio,
    r.total_post_score,
    r.upvotes_rcvd,
    r.downvotes_rcvd,
    r.total_score_all,
    r.bounty_started,
    r.bounty_awarded,
    r.comments_by_user,
    r.comments_by_anon,
    r.comment_score_sum,
    r.top_tag,
    r.top_tag_posts,
    r.top_tag_answers,
    r.top_tag_questions,
    r.top_tag_score,
    r.last_activity,
    r.rn_rep,
    r.dr_score,
    r.answers_decile,
    m.sample_questions,
    m.sample_answers,
    m.avg_q_score_nonzero,
    m.avg_q_views,
    m.closed_posts,
    m.duplicate_marked,
    m.distinct_dupe_targets,
    m.max_close_events_on_post,
    case
        when coalesce(r.answers,0) > 100 and r.accept_ratio >= 0.6 then 'elite'
        when coalesce(r.answers,0) > 25 and r.accept_ratio >= 0.4 then 'strong'
        when coalesce(r.answers,0) > 5 then 'active'
        else 'newbie'
    end as contributor_band,
    case
        when r.top_tag is null then null
        when position('c#' in r.top_tag) > 0 then 'dotnet'
        when r.top_tag like 'sql%' or r.top_tag like 'postgres%' or r.top_tag like 'mysql%' or r.top_tag like 'sqlite%' then 'databases'
        when r.top_tag similar to '(python|pandas|numpy|django)%' then 'python'
        else 'other'
    end as top_tag_cluster
from ranked r
left join metrics m on m.user_id = r.user_id
where (r.reputation > 1000 or (r.total_q_a >= 10 and r.total_score_all > 50))
  and coalesce(r.displayname,'') not ilike '%bot%'
order by r.rn_rep
limit 200;