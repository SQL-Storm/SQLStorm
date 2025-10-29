-- {"query": "253.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2510} 
with recent_active_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.lastaccessdate,
        u.location,
        coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown') as domain_host,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(distinct date_trunc('day', b.date)) as distinct_badge_days,
        max(b.date) as last_badge_date
    from users u
    left join badges b
      on b.userid = u.id
    where u.lastaccessdate > now() - interval '365 days'
    group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate, u.location, domain_host
),
question_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as questions,
        count(*) filter (where p.posttypeid = 2) as answers,
        sum(coalesce(p.score,0)) filter (where p.posttypeid in (1,2)) as qa_score,
        sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as question_views,
        avg(nullif(p.answercount,0)) as avg_answercount_nonzero,
        count(*) filter (where p.closeddate is not null) as closed_posts,
        max(p.lastactivitydate) as last_post_activity
    from posts p
    where p.owneruserid is not null
      and p.creationdate > now() - interval '730 days'
    group by p.owneruserid
),
tag_expertise as (
    select
        q.owneruserid as user_id,
        t.tagname,
        count(*) as tag_q_count,
        sum(q.score) as tag_q_score,
        dense_rank() over (partition by q.owneruserid order by count(*) desc, sum(q.score) desc, min(q.creationdate)) as tag_rank
    from posts q
    join lateral unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tag(tagname)
      on true
    where q.posttypeid = 1
      and q.owneruserid is not null
      and q.creationdate > now() - interval '1095 days'
    group by q.owneruserid, t.tagname
),
top_tags as (
    select user_id,
           string_agg(tagname, ', ' order by tagname) as top_3_tags
    from tag_expertise
    where tag_rank <= 3
    group by user_id
),
comment_insights as (
    select
        c.userid as user_id,
        count(*) as comments_count,
        sum(c.score) as comment_score,
        percentile_cont(0.9) within group (order by c.score) as p90_comment_score,
        avg(length(c.text)) as avg_comment_len,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
      and c.creationdate > now() - interval '365 days'
    group by c.userid
),
vote_summary as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total,
        max(v.creationdate) as last_vote_date
    from votes v
    where v.userid is not null
      and v.creationdate > now() - interval '730 days'
    group by v.userid
),
dup_network as (
    select
        pl.postid,
        pl.relatedpostid,
        pl.linktypeid,
        case when pl.linktypeid = 3 then 1 else 0 end as is_duplicate
    from postlinks pl
    where pl.linktypeid in (1,3)
),
closure_reasons as (
    select
        ph.postid,
        max(ph.creationdate) as last_close_date,
        max((regexp_matches(ph.comment, '^[0-9]+'))[1])::int as last_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid = 10
    group by ph.postid
),
user_quality as (
    select
        qa.user_id,
        sum(case when d.is_duplicate = 1 then 1 else 0 end) as duplicates_links,
        count(distinct d.relatedpostid) filter (where d.is_duplicate = 1) as distinct_dupe_targets,
        count(*) filter (where cr.last_close_reason_id is not null) as closed_q_with_reason,
        count(*) filter (where cr.last_close_reason_id = 101) as closed_q_duplicate_reason
    from posts q
    join question_activity qa
      on qa.user_id = q.owneruserid
    left join dup_network d
      on d.postid = q.id
    left join closure_reasons cr
      on cr.postid = q.id
    where q.posttypeid = 1
    group by qa.user_id
),
ranked_users as (
    select
        rau.*,
        qa.questions,
        qa.answers,
        qa.qa_score,
        qa.question_views,
        qa.avg_answercount_nonzero,
        qa.closed_posts,
        tt.top_3_tags,
        ci.comments_count,
        ci.comment_score,
        ci.p90_comment_score,
        ci.avg_comment_len,
        vs.upvotes_cast,
        vs.downvotes_cast,
        vs.bounty_total,
        uq.duplicates_links,
        uq.distinct_dupe_targets,
        uq.closed_q_with_reason,
        uq.closed_q_duplicate_reason,
        greatest(coalesce(qa.last_post_activity, timestamp 'epoch'),
                 coalesce(ci.last_comment_date, timestamp 'epoch'),
                 coalesce(vs.last_vote_date, timestamp 'epoch'),
                 coalesce(rau.last_badge_date, timestamp 'epoch')) as last_any_activity,
        row_number() over (
          order by
            coalesce(qa.qa_score,0) desc,
            coalesce(qa.question_views,0) desc,
            coalesce(vs.upvotes_cast,0) desc,
            coalesce(rau.reputation,0) desc,
            coalesce(ci.comment_score,0) desc
        ) as global_rank
    from recent_active_users rau
    left join question_activity qa on qa.user_id = rau.user_id
    left join top_tags tt on tt.user_id = rau.user_id
    left join comment_insights ci on ci.user_id = rau.user_id
    left join vote_summary vs on vs.user_id = rau.user_id
    left join user_quality uq on uq.user_id = rau.user_id
),
domain_stats as (
    select
        domain_host,
        count(*) as users_in_domain,
        avg(reputation) as avg_rep_domain,
        percentile_cont(0.5) within group (order by reputation) as median_rep_domain
    from recent_active_users
    group by domain_host
),
user_outliers as (
    select
        ru.user_id,
        ru.displayname,
        ru.domain_host,
        ru.reputation,
        ds.users_in_domain,
        ds.avg_rep_domain,
        ds.median_rep_domain,
        case when ru.reputation > ds.avg_rep_domain * 2 then 1 else 0 end as is_high_rep_outlier
    from ranked_users ru
    join domain_stats ds using (domain_host)
),
final_scored as (
    select
        ru.*,
        uo.users_in_domain,
        uo.avg_rep_domain,
        uo.median_rep_domain,
        uo.is_high_rep_outlier,
        -- composite score mixing multiple behaviors with caps and null-safety
        least(10000,
            coalesce(qa_score,0) * 4
          + coalesce(question_views,0) * 0.02
          + coalesce(upvotes_cast,0) * 3
          - coalesce(downvotes_cast,0)
          + coalesce(comments_count,0) * 0.1
          + coalesce(bounty_total,0) * 0.5
          + coalesce(gold_badges,0) * 100
          + coalesce(silver_badges,0) * 40
          + coalesce(bronze_badges,0) * 15
          - coalesce(closed_posts,0) * 5
          - coalesce(closed_q_duplicate_reason,0) * 7
        ) as composite_score
    from ranked_users ru
    left join user_outliers uo on uo.user_id = ru.user_id
),
quartiles as (
    select
        fs.*,
        ntile(4) over (order by composite_score desc nulls last) as score_quartile,
        dense_rank() over (order by coalesce(top_3_tags,'') nulls last) as tag_bucket
    from final_scored fs
)
select
    q.global_rank,
    q.user_id,
    coalesce(nullif(q.displayname, ''), '(anonymous)') as displayname,
    q.reputation,
    q.domain_host,
    q.users_in_domain,
    q.avg_rep_domain::numeric(18,2) as avg_rep_domain,
    q.median_rep_domain::numeric(18,2) as median_rep_domain,
    q.is_high_rep_outlier,
    q.gold_badges,
    q.silver_badges,
    q.bronze_badges,
    q.distinct_badge_days,
    q.questions,
    q.answers,
    q.qa_score,
    q.question_views,
    q.avg_answercount_nonzero::numeric(18,2) as avg_answercount_nonzero,
    q.closed_posts,
    coalesce(q.top_3_tags, '(none)') as top_3_tags,
    q.comments_count,
    q.comment_score,
    q.p90_comment_score,
    q.avg_comment_len::numeric(18,2) as avg_comment_len,
    q.upvotes_cast,
    q.downvotes_cast,
    q.bounty_total,
    q.duplicates_links,
    q.distinct_dupe_targets,
    q.closed_q_with_reason,
    q.closed_q_duplicate_reason,
    q.last_any_activity,
    q.score_quartile,
    q.tag_bucket,
    q.composite_score::numeric(18,2) as composite_score,
    -- sanity checks and complex predicate flags
    case when q.reputation < 1 and q.qa_score > 100 then 'suspicious' else 'ok' end as anomaly_flag,
    case when q.last_any_activity > now() - interval '30 days' then true else false end as active_30d
from quartiles q
where
    -- complicated predicate mixing null logic, string ops, and activity windows
    coalesce(q.questions,0) + coalesce(q.answers,0) > 0
    and (
        q.domain_host not ilike any (array['%spam%','%example.com%'])
        or (q.gold_badges + q.silver_badges) >= 3
    )
    and (
        q.top_3_tags is null
        or position('sql' in lower(q.top_3_tags)) > 0
        or q.qa_score >= all (
            select coalesce(qa.qa_score,0)
            from ranked_users qa
            where qa.domain_host = q.domain_host
              and qa.user_id <> q.user_id
        )
    )
order by q.global_rank
limit 200;