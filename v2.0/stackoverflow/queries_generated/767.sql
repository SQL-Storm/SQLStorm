-- {"query": "767.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2945} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_normalized,
        row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score,0)) as post_score,
        sum(coalesce(p.viewcount,0)) as views,
        max(p.lastactivitydate) as last_post_activity,
        avg(nullif(p.commentcount,0)) as avg_commentcount_nonzero
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
    group by p.owneruserid
),
user_badges as (
    select
        b.userid as user_id,
        count(*) as badge_count,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        max(b.date) as last_badge_date
    from badges b
    where b.date >= (select coalesce(min(u.creationdate), now() - interval '365 days') from users u)
    group by b.userid
),
question_metrics as (
    select
        p.owneruserid as user_id,
        count(*) as questions,
        avg(coalesce(p.score,0)) as avg_q_score,
        count(*) filter (where p.acceptedanswerid is not null) as accepted_count,
        avg(case when p.acceptedanswerid is not null then 1 else 0 end::numeric) as accept_rate,
        percentile_cont(0.5) within group (order by coalesce(p.viewcount,0)) as med_q_views,
        min(p.creationdate) as first_q_date,
        max(p.creationdate) as last_q_date
    from posts p
    where p.posttypeid = 1
    group by p.owneruserid
),
answer_metrics as (
    select
        p.owneruserid as user_id,
        count(*) as answers,
        avg(coalesce(p.score,0)) as avg_a_score,
        sum(case when v.votetypeid = 1 then 1 else 0 end) as accepted_flags_from_votes
    from posts p
    left join votes v
      on v.postid = p.id
     and v.votetypeid in (1)
    where p.posttypeid = 2
    group by p.owneruserid
),
engagement_windows as (
    select
        c.userid as user_id,
        date_trunc('month', c.creationdate) as period,
        count(*) as comments_in_month,
        sum(c.score) as comment_score_in_month,
        row_number() over (partition by c.userid order by date_trunc('month', c.creationdate) desc) as recency_rank
    from comments c
    where c.userid is not null
    group by c.userid, date_trunc('month', c.creationdate)
),
latest_engagement as (
    select
        e.user_id,
        e.period as latest_comment_month,
        e.comments_in_month,
        e.comment_score_in_month
    from engagement_windows e
    where e.recency_rank = 1
),
tag_pref as (
    select
        q.owneruserid as user_id,
        lower(trim(both '<>' from unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')))) as tagname,
        count(*) as tag_uses,
        sum(q.score) as tag_score
    from posts q
    where q.posttypeid = 1
      and q.tags is not null
    group by q.owneruserid, lower(trim(both '<>' from unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><'))))
),
top_tag as (
    select user_id, tagname, tag_uses, tag_score
    from (
        select
            t.*,
            row_number() over (partition by t.user_id order by tag_uses desc, tag_score desc, tagname asc) as rn
        from tag_pref t
    ) x
    where rn = 1
),
postlink_stats as (
    select
        p.owneruserid as user_id,
        count(*) filter (where pl.linktypeid = 3) as duplicates_declared,
        count(*) filter (where pl.linktypeid = 1) as linked_refs
    from posts p
    left join postlinks pl
      on pl.postid = p.id
    group by p.owneruserid
),
history_events as (
    select
        ph.userid as user_id,
        count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35,36)) as mod_event_count,
        count(*) filter (where ph.posthistorytypeid = 50) as community_bumps,
        min(ph.creationdate) as first_event,
        max(ph.creationdate) as last_event
    from posthistory ph
    where ph.userid is not null
    group by ph.userid
),
user_quality as (
    select
        u.id as user_id,
        case
            when u.reputation >= 100000 then 'legend'
            when u.reputation >= 25000 then 'veteran'
            when u.reputation >= 5000 then 'pro'
            when u.reputation >= 500 then 'regular'
            else 'newbie'
        end as rep_band,
        (coalesce(u.upvotes,0) - coalesce(u.downvotes,0))::numeric / nullif(u.views,0) as vote_view_ratio
    from users u
),
activity_density as (
    select
        p.owneruserid as user_id,
        count(*) as total_posts,
        extract(epoch from (max(p.creationdate) - min(p.creationdate))) / 86400.0 as active_span_days,
        count(*)::numeric / nullif(extract(epoch from (max(p.creationdate) - min(p.creationdate))) / 86400.0, 0) as posts_per_day_span
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
recent_hot_questions as (
    select
        q.id as post_id,
        q.owneruserid as user_id,
        q.creationdate,
        q.score,
        q.viewcount,
        q.title,
        exists (
            select 1
            from posthistory ph
            where ph.postid = q.id
              and ph.posthistorytypeid in (52)
        ) as became_hot_flag
    from posts q
    where q.posttypeid = 1
      and q.creationdate >= now() - interval '180 days'
),
ranked_users as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.location,
        ru.websiteurl_normalized,
        ua.q_count,
        ua.a_count,
        ua.post_score,
        ua.views,
        ua.last_post_activity,
        ua.avg_commentcount_nonzero,
        ub.badge_count,
        ub.gold_badges,
        ub.silver_badges,
        ub.bronze_badges,
        ub.last_badge_date,
        qm.questions,
        qm.avg_q_score,
        qm.accepted_count,
        qm.accept_rate,
        qm.med_q_views,
        am.answers,
        am.avg_a_score,
        am.accepted_flags_from_votes,
        le.latest_comment_month,
        le.comments_in_month,
        le.comment_score_in_month,
        tt.tagname as top_tag,
        tt.tag_uses as top_tag_uses,
        ps.duplicates_declared,
        ps.linked_refs,
        he.mod_event_count,
        he.community_bumps,
        he.first_event,
        he.last_event,
        uq.rep_band,
        uq.vote_view_ratio,
        ad.total_posts,
        ad.active_span_days,
        ad.posts_per_day_span,
        coalesce(sum(case when rhq.became_hot_flag then 1 else 0 end) over (partition by ru.user_id),0) as recent_hot_qs,
        row_number() over (
            order by
                coalesce(ua.post_score,0) desc,
                coalesce(ub.badge_count,0) desc,
                coalesce(ad.posts_per_day_span,0) desc,
                coalesce(qm.accept_rate,0) desc,
                ru.reputation desc,
                ru.user_id
        ) as global_rank
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_badges ub on ub.user_id = ru.user_id
    left join question_metrics qm on qm.user_id = ru.user_id
    left join answer_metrics am on am.user_id = ru.user_id
    left join latest_engagement le on le.user_id = ru.user_id
    left join top_tag tt on tt.user_id = ru.user_id
    left join postlink_stats ps on ps.user_id = ru.user_id
    left join history_events he on he.user_id = ru.user_id
    left join user_quality uq on uq.user_id = ru.user_id
    left join activity_density ad on ad.user_id = ru.user_id
    left join recent_hot_questions rhq on rhq.user_id = ru.user_id
),
dupe_groups as (
    select
        p.owneruserid as user_id,
        count(*) as dupe_posts,
        count(distinct pl.relatedpostid) as unique_dupe_targets
    from posts p
    join postlinks pl
      on pl.postid = p.id
     and pl.linktypeid = 3
    where p.posttypeid = 1
    group by p.owneruserid
),
stringy as (
    select
        r.user_id,
        trim(both ' ' from coalesce(r.displayname, '(anon)')) as clean_name,
        regexp_replace(coalesce(r.location,''), '\s+', ' ', 'g') as clean_location,
        case
            when r.websiteurl_normalized ilike 'http%' then r.websiteurl_normalized
            when r.websiteurl_normalized = 'n/a' then null
            else 'http://' || r.websiteurl_normalized
        end as homepage_url
    from ranked_users r
),
final_scores as (
    select
        r.*,
        coalesce(dg.dupe_posts,0) as dupe_posts,
        coalesce(dg.unique_dupe_targets,0) as unique_dupe_targets,
        greatest(0,
            coalesce(r.post_score,0) * 0.50
          + coalesce(r.badge_count,0) * 0.25
          + coalesce(r.views,0) * 0.05
          + coalesce(r.answers,0) * 0.10
          + coalesce(r.questions,0) * 0.05
          + coalesce(r.accept_rate,0) * 10.0
          + coalesce(r.posts_per_day_span,0) * 2.0
          + coalesce(r.recent_hot_qs,0) * 3.0
          - coalesce(dg.dupe_posts,0) * 0.50
        ) as composite_score
    from ranked_users r
    left join dupe_groups dg on dg.user_id = r.user_id
),
topn as (
    select
        fs.*,
        dense_rank() over (order by fs.composite_score desc, fs.global_rank asc) as dense_rnk
    from final_scores fs
)
select
    t.user_id,
    s.clean_name as displayname,
    s.clean_location as location,
    s.homepage_url,
    t.rep_band,
    t.reputation,
    t.global_rank,
    t.composite_score,
    t.post_score,
    t.views,
    t.q_count,
    t.a_count,
    t.questions,
    t.answers,
    t.avg_q_score,
    t.avg_a_score,
    t.accept_rate,
    t.accepted_count,
    t.accepted_flags_from_votes,
    t.med_q_views,
    t.latest_comment_month,
    t.comments_in_month,
    t.comment_score_in_month,
    t.badge_count,
    t.gold_badges,
    t.silver_badges,
    t.bronze_badges,
    t.last_badge_date,
    t.top_tag,
    t.top_tag_uses,
    t.duplicates_declared,
    t.linked_refs,
    t.dupe_posts,
    t.unique_dupe_targets,
    t.mod_event_count,
    t.community_bumps,
    t.first_event,
    t.last_event,
    t.total_posts,
    t.active_span_days,
    t.posts_per_day_span,
    t.recent_hot_qs
from topn t
join stringy s on s.user_id = t.user_id
where t.dense_rnk <= 100
  and coalesce(t.location,'') not ilike '%stack overflow%'
  and (
        t.websiteurl_normalized is null
        or t.websiteurl_normalized not ilike '%example.com%'
        or position('.com' in coalesce(t.websiteurl_normalized,'')) > 0
      )
  and (t.avg_commentcount_nonzero is null or t.avg_commentcount_nonzero >= 0)
order by t.composite_score desc, t.global_rank asc, t.user_id asc;