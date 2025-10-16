-- {"query": "16.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2238} 
with recursive tag_hierarchy(tag, depth, path) as (
    -- build a synthetic tag co-occurrence "hierarchy" based on tags in questions
    select
        lower(trim(tg)) as tag,
        1 as depth,
        lower(trim(tg)) as path
    from (
        select unnest(string_to_array(substring(Tags,2,length(Tags)-2), '><')) as tg
        from Posts
        where PostTypeId = 1 and Tags is not null
        limit 2000
    ) s
    union all
    select
        lower(trim(tg2)) as tag,
        th.depth + 1,
        th.path || '>' || lower(trim(tg2))
    from tag_hierarchy th
    join lateral (
        select unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><')) as tg2, p.Id
        from Posts p
        where p.PostTypeId = 1
          and p.Tags is not null
          and position(th.tag in lower(p.Tags)) > 0
        limit 5
    ) x on true
    where th.depth < 3
),
user_activity as (
    -- summarize user activity with window functions and null-aware aggregates
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(u.Reputation,0) as Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id) as AnswersCount,
        sum(coalesce(vt_up.cnt,0)) over (partition by u.Id) as UpVotesReceived,
        sum(coalesce(vt_down.cnt,0)) over (partition by u.Id) as DownVotesReceived,
        row_number() over (order by coalesce(u.Reputation,0) desc, u.Id) as ReputationRank,
        max(u.LastAccessDate) over (partition by u.Id) as LastSeen
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join lateral (
        select PostId, count(*) as cnt from Votes where VoteTypeId = 2 and PostId in (select Id from Posts where OwnerUserId = u.Id) group by PostId
    ) vt_up on true
    left join lateral (
        select PostId, count(*) as cnt from Votes where VoteTypeId = 3 and PostId in (select Id from Posts where OwnerUserId = u.Id) group by PostId
    ) vt_down on true
    where u.Id is not null
    group by u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
),
popular_answers as (
    -- top answers per question including an interesting score metric with NULL logic and string ops
    select distinct on (a.ParentId)
        a.ParentId as QuestionId,
        a.Id as AnswerId,
        coalesce(a.Score,0) as AnswerScore,
        coalesce(q.Score,0) as QuestionScore,
        coalesce(a.CreationDate, a.LastActivityDate) as AnswerCreatedAt,
        coalesce(a.OwnerUserId, -1) as AnswerOwner,
        case
            when a.Id = q.AcceptedAnswerId then 'accepted'
            when coalesce(a.Score,0) >= greatest(5, coalesce(q.Score,0)/2) then 'high'
            when coalesce(a.Score,0) <= 0 then 'low'
            else 'normal'
        end as AnswerTag,
        left(replace(coalesce(a.Body,''), E'\n',' '), 200) as Snippet
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    where a.PostTypeId = 2
    order by a.ParentId, (coalesce(a.Score,0) * 1000 + (case when a.Id = q.AcceptedAnswerId then 100000 else 0 end)) desc, a.CreationDate asc
),
linked_questions as (
    select
        pl.PostId as FromPost,
        pl.RelatedPostId as ToPost,
        lt.Name as LinkType,
        pl.CreationDate as LinkCreated
    from PostLinks pl
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where pl.PostId is not null and pl.RelatedPostId is not null
),
recent_edits as (
    select ph.PostId, ph.Id as HistoryId, ph.PostHistoryTypeId, ph.CreationDate, ph.UserId, ph.Comment,
           dense_rank() over (partition by ph.PostId order by ph.CreationDate desc) as rev_rank
    from PostHistory ph
    where ph.PostId is not null
),
question_tag_stats as (
    select
        lower(trim(tg)) as tag,
        count(distinct p.Id) as questions,
        avg(coalesce(p.ViewCount,0)) as avg_views,
        percentile_disc(0.5) within group (order by coalesce(p.Score,0)) as median_score,
        sum(coalesce(p.AnswerCount,0)) as total_answers,
        sum(case when p.AcceptedAnswerId is not null then 1 else 0 end) as accepted_count
    from Posts p
    cross join lateral (
        select unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><')) as tg
    ) tt
    where p.PostTypeId = 1 and p.Tags is not null
    group by lower(trim(tg))
),
complex_user_profile as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionsCount,
        ua.AnswersCount,
        ua.UpVotesReceived,
        ua.DownVotesReceived,
        coalesce(bc.BadgeSummary,'') as BadgeSummary,
        coalesce(tag_best.tag,'') as FavoriteTag,
        case
            when ua.Reputation >= 20000 then 'elite'
            when ua.Reputation >= 5000 then 'expert'
            when ua.Reputation >= 1000 then 'regular'
            else 'novice'
        end as Tier,
        greatest(0, ua.UpVotesReceived - ua.DownVotesReceived) as NetPositiveVotes
    from user_activity ua
    left join (
        select UserId, string_agg(Name || ':' || Class, ',') as BadgeSummary
        from Badges
        group by UserId
    ) bc on bc.UserId = ua.UserId
    left join lateral (
        select qt.tag
        from (
            select lower(trim(un) ) as tag, count(*) as cnt
            from Posts p cross join lateral unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><')) un
            where p.OwnerUserId = ua.UserId and p.PostTypeId = 1
            group by lower(trim(un))
            order by cnt desc nulls last
            limit 1
        ) qt
    ) tag_best on true
    where ua.ReputationRank <= 1000
)
select
    q.Id as QuestionId,
    q.Title,
    q.OwnerUserId,
    coalesce(u.DisplayName, 'unknown') as OwnerName,
    q.CreationDate,
    q.Score as QuestionScore,
    qa.AnswerId,
    qa.AnswerScore,
    qa.AnswerTag,
    qa.Snippet,
    qs.tag as PrimaryTag,
    qs.questions as TagQuestionCount,
    qs.avg_views as TagAvgViews,
    qs.median_score as TagMedianScore,
    lq.LinkType,
    lq.ToPost as LinkedTo,
    re.RevisionGUID is not null as RecentlyEdited,
    re.rev_rank,
    cu.Tier as OwnerTier,
    cu.BadgeSummary,
    cu.FavoriteTag,
    th.max_depth,
    th.sample_path,
    -- computed synthetic complexity metric combining many facets (NULL-aware)
    (
      coalesce(q.Score,0) * 10
      + coalesce(qa.AnswerScore,0) * 50
      + (case when qa.AnswerTag = 'accepted' then 100000 else 0 end)
      + coalesce(q.ViewCount,0) / nullif(greatest(1, qs.tag_question_count_or_one::numeric), 0)
      - coalesce(cu.DownVotesReceived,0) * 5
      + coalesce((select count(*) from Comments c where c.PostId = q.Id),0) * 2
    ) as ComplexityScore
from Posts q
left join Posts qdup on qdup.Id = q.AcceptedAnswerId
left join popular_answers qa on qa.QuestionId = q.Id
left join Users u on u.Id = q.OwnerUserId
left join lateral (
    select tag as primary_tag, questions, avg_views, median_score
    from question_tag_stats tts
    where position(lower(tts.tag) in coalesce(lower(q.Tags),'')) > 0
    order by tts.questions desc nulls last
    limit 1
) qs on true
left join linked_questions lq on lq.FromPost = q.Id and lq.LinkType = 'Duplicate'
left join (
    select PostId, max(rev_rank) as rev_rank, bool_or(RevisionGUID is not null) as has_guid, max(RevisionGUID) as RevisionGUID
    from (
        select ph.PostId, ph.RevisionGUID, dense_rank() over (partition by ph.PostId order by ph.CreationDate desc) as rev_rank
        from PostHistory ph
    ) s
    group by PostId
) re on re.PostId = q.Id
left join (
    -- pick a sample path and max depth from tag_hierarchy for any tag on this question
    select tag as sample_tag, max(depth) as max_depth, string_agg(distinct path, ' | ' order by path) as sample_path
    from tag_hierarchy
    group by tag
) th on position(th.sample_tag in coalesce(lower(q.Tags),'')) > 0
left join complex_user_profile cu on cu.UserId = q.OwnerUserId
where q.PostTypeId = 1
  and q.CreationDate >= now() - interval '5 years'
  and (coalesce(q.Score,0) > -5 or q.ViewCount > 1000)
order by ComplexityScore desc nulls last
limit 250;