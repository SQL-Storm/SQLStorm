-- {"query": "760.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1672} 
with RecursivePostPaths as (
    select 
        p.Id as PostId,
        p.ParentId,
        array[p.Id] as Path,
        1 as Depth
    from Posts p
    where p.PostTypeId = 2 -- Answers

    union all

    select 
        p.Id,
        p.ParentId,
        r.Path || p.Id,
        r.Depth + 1
    from Posts p
    join RecursivePostPaths r on p.ParentId = r.PostId
    where r.Depth < 5
), UserBadgeRankings as (
    select
        b.UserId,
        b.Class,
        b.Name,
        row_number() over (partition by b.UserId order by b.Date desc, b.Class) as BadgeRank
    from Badges b
), TopBadgesPerUser as (
    select
        UserId,
        Class,
        Name
    from UserBadgeRankings
    where BadgeRank = 1
), UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as TotalQuestions,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as TotalAnswers,
        sum(v.VoteCount) as TotalVotesReceived,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select 
            v.PostId, count(*) as VoteCount
        from Votes v
        group by v.PostId
    ) v on v.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
), LatestCloseReasons as (
    select distinct on (ph.PostId)
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id and ph.PostHistoryTypeId = 10
    where ph.PostHistoryTypeId = 10
    order by ph.PostId, ph.CreationDate desc
), PostWithDetails as (
    select 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        lcr.CloseReasonName,
        case 
            when p.Tags is null then array[]::text[]
            else string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')
        end as TagArray
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join LatestCloseReasons lcr on lcr.PostId = p.Id
), AggregatedVotes as (
    select 
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount, 0) else 0 end) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
), QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        q.OwnerName as QuestionOwner,
        q.OwnerReputation as QuestionOwnerReputation,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId is not null then 1 else 0 end) as AnsweredByKnownUsers,
        count(distinct a.OwnerUserId) as UniqueAnswerers
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.OwnerName, q.OwnerReputation
), TopTags as (
    select
        t.TagName,
        t.Count,
        coalesce(t.ExcerptPostId, 0) as ExcerptPostId,
        coalesce(t.WikiPostId, 0) as WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        row_number() over (order by t.Count desc) as TagRank
    from Tags t
), TagPostCounts as (
    select
        unnest(
            case 
                when p.Tags is null then array[]::text[]
                else string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')
            end
        ) as TagName,
        count(p.Id) as PostsWithTag
    from Posts p
    where p.PostTypeId = 1
    group by TagName
), UserCommentStats as (
    select
        c.UserId,
        u.DisplayName,
        count(c.Id) as CommentCount,
        avg(c.Score) as AvgCommentScore,
        max(c.Score) as MaxCommentScore,
        sum(case when c.Text ilike '%bug%' then 1 else 0 end) as BugMentions
    from Comments c
    left join Users u on u.Id = c.UserId
    group by c.UserId, u.DisplayName
)
select
    qas.QuestionId,
    qas.Title,
    qas.QuestionDate,
    qas.QuestionOwner,
    qas.QuestionOwnerReputation,
    qas.AnswerCount,
    qas.AvgAnswerScore,
    qas.MaxAnswerScore,
    qas.AnsweredByKnownUsers,
    qas.UniqueAnswerers,
    av.UpVotes,
    av.DownVotes,
    av.TotalBounty,
    pd.ClosedDate,
    pd.CloseReasonName,
    array_to_string(pd.TagArray, ', ') as Tags,
    tb.Class as TopBadgeClass,
    tb.Name as TopBadgeName,
    uac.CommentCount,
    uac.AvgCommentScore,
    uac.BugMentions,
    row_number() over (partition by qas.QuestionOwner order by qas.QuestionDate desc) as RecentQuestionRank,
    coalesce(rpp.Depth, 0) as AnswerRecursionDepth
from QuestionAnswerStats qas
left join AggregatedVotes av on av.PostId = qas.QuestionId
left join PostWithDetails pd on pd.Id = qas.QuestionId
left join TopBadgesPerUser tb on tb.UserId = (
    select u.Id from Users u where u.DisplayName = qas.QuestionOwner limit 1
)
left join UserCommentStats uac on uac.UserId = (
    select u.Id from Users u where u.DisplayName = qas.QuestionOwner limit 1
)
left join RecursivePostPaths rpp on rpp.PostId = (
    select a.Id from Posts a where a.ParentId = qas.QuestionId order by a.Score desc limit 1
)
where qas.AnswerCount > 0
  and (pd.ClosedDate is null or pd.ClosedDate > now() - interval '180 days')
  and (pd.CloseReasonName is null or pd.CloseReasonName not ilike '%duplicate%')
order by qas.AnswerCount desc, qas.AvgAnswerScore desc
limit 100;