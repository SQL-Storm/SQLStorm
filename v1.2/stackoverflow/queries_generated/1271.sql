-- {"query": "1271.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1554} 
with RecursiveTagTree as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as level,
        array[t.Id] as path
    from Tags t
    where t.IsModeratorOnly = 0
    union all
    select
        c.Id,
        c.TagName,
        c.Count,
        c.ExcerptPostId,
        c.WikiPostId,
        r.level + 1 as level,
        path || c.Id
    from Tags c
    inner join RecursiveTagTree r
    on c.Id <> all(r.path)
    and c.Count < r.Count
    where c.IsModeratorOnly = 0
),
UserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct b.Id) as BadgeCount,
        max(p.CreationDate) as LastPostDate,
        min(ph.CreationDate) as FirstEdit,
        coalesce(sum(vs.UpVotes), 0) as TotalUpVotes,
        coalesce(sum(vd.DownVotes), 0) as TotalDownVotes,
        rank() over (order by count(distinct p.Id) desc) as ActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join (
        select OwnerUserId, count(*) as UpVotes 
        from Posts p 
        where p.OwnerUserId is not null and p.Score > 0 
        group by OwnerUserId
    ) vs on vs.OwnerUserId = u.Id
    left join (
        select OwnerUserId, count(*) as DownVotes
        from Posts p 
        where p.OwnerUserId is not null and p.Score < 0 
        group by OwnerUserId
    ) vd on vd.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id and ph.PostId in (select Id from Posts where OwnerUserId = u.Id)
    group by u.Id, u.DisplayName
),
PostRankings as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Tags,
        row_number() over (
            partition by p.PostTypeId 
            order by p.Score desc, p.ViewCount desc, p.CreationDate asc
        ) as RankInType,
        max(p.Score) over (partition by p.PostTypeId) as MaxScoreInType
    from Posts p
    where p.PostTypeId in (1, 2)
),
ClosedOverdueQuestions as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        cht.Name as CloseType,
        ph.CreationDate as ClosedDate,
        now()::date - cast(p.CreationDate as date) as DaysOpenBeforeClose,
        timediff(p.ClosedDate, p.CreationDate) as ClosureLatency
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes cht on cht.Id = cast(ph.Comment as integer)
    where p.PostTypeId = 1 and p.ClosedDate is not null
),
AnswersWithAcceptedInfo AS (
    select 
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        case when q.AcceptedAnswerId = a.Id then 1 else 0 end as IsAccepted,
        u.DisplayName as AnswerOwner,
        q.Title as QuestionTitle,
        q.OwnerUserId as QuestionOwner,
        q.Score as QuestionScore
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
UserCommentsOverview AS (
    select
        c.UserId,
        u.DisplayName,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        sum(case when c.Score is null then 0 else c.Score end) as CommentScoreSum,
        count(distinct c.PostId) as PostsCommentedOn,
        count(distinct case when pos.PostTypeId = 1 then c.PostId else null end) as QuestionsCommented,
        count(distinct case when pos.PostTypeId = 2 then c.PostId else null end) as AnswersCommented
    from Comments c
    left join Users u on u.Id = c.UserId
    left join Posts pos on pos.Id = c.PostId
    group by c.UserId, u.DisplayName
)

select 
    ua.UserId,
    ua.DisplayName,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.BadgeCount,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.LastPostDate,
    ua.FirstEdit,
    venue.CommentCount as TotalComments,
    venue.CommentScoreSum,
    venue.QuestionsCommented,
    venue.AnswersCommented,
    pr.RankInType as UserTopPostRank,
    pr.MaxScoreInType,
    coalesce(string_agg(distinct split_part(pt.Name || ':' || cast(uat.level as varchar), ':', 2), ',' order by uat.level), 'N/A') as TagPopularityLevels,
    closedq.CloseType,
    closedq.DaysOpenBeforeClose,
    (
        select count(*)
        from Votes v 
        where v.PostId = any(
            select Id from Posts p2 where p2.OwnerUserId = ua.UserId
        ) 
        and v.CreationDate > now() - interval '90 days'
    ) as RecentVotesCount,
    (
        select avg(score.avg_score) from (
            select avg(score) as avg_score
            from Posts p3
            where p3.OwnerUserId = ua.UserId
            group by p3.PostTypeId
        ) score
    ) as AvgScoreAcrossPostTypes

from UserActivity ua
left join UserCommentsOverview venue on venue.UserId = ua.UserId
left join PostRankings pr on pr.OwnerUserId = ua.UserId and pr.RankInType = 1
left join RecursiveTagTree uat on uat.Id in (
    select distinct unnest(string_to_array(
        coalesce(post.Tags, ''), '<>')::int[]
    ) from Posts post where post.OwnerUserId = ua.UserId limit 1
)
left join PostTypes pt on pr.PostTypeId = pt.Id
left join ClosedOverdueQuestions closedq on closedq.OwnerUserId = ua.UserId
where ua.QuestionCount + ua.AnswerCount > 0
and (ua.TotalUpVotes > ua.TotalDownVotes or ua.BadgeCount > 5)
order by ua.BadgeCount desc, ua.TotalUpVotes desc, ua.QuestionCount desc
limit 50;