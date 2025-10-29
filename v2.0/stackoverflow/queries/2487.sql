with recursive RecursivePostRelations as (
    select 
        p.Id as RootPostId,
        p.Id as CurrentPostId,
        0 as Depth
    from Posts p 
    where p.PostTypeId = 1
    union all
    select
        r.RootPostId,
        pl.RelatedPostId,
        r.Depth + 1
    from RecursivePostRelations r
    join PostLinks pl on pl.PostId = r.CurrentPostId
    where r.Depth < 3
), LatestUserActivity as (
    select
        u.Id,
        coalesce(u.LastAccessDate, u.CreationDate) as LastActive,
        row_number() over (partition by u.Id order by u.LastAccessDate desc, u.CreationDate desc) as rn
    from Users u
), BadgeSummary as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        string_agg(distinct b.Name, ', ' order by b.Name) as BadgesList
    from Badges b
    group by b.UserId, b.Class
), PostScoreRankings as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreRank
    from Posts p
    where p.Score is not null
), QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        count(a.Id) filter (where a.Id is not null) as AnswerCount,
        coalesce(max(a.Score), 0) as MaxAnswerScore,
        coalesce(avg(a.Score), 0) as AvgAnswerScore,
        count(distinct pl.Id) filter (where pl.LinkTypeId = 3) as DuplicateCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join PostLinks pl on pl.PostId = q.Id
    where q.PostTypeId = 1
    group by q.Id
), TopAnswerers as (
    select 
        a.OwnerUserId,
        count(a.Id) as AnswersGiven,
        avg(a.Score) as AvgAnswerScore,
        rank() over (order by count(a.Id) desc, avg(a.Score) desc) as UserRank
    from Posts a
    where a.PostTypeId = 2
        and a.OwnerUserId is not null
    group by a.OwnerUserId
    having count(a.Id) > 10
), UserVoteImpact as (
    select 
        u.Id as UserId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesReceived,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesReceived,
        sum(case when v.VoteTypeId = 6 then 1 else 0 end) as CloseVotesCast,
        count(v.Id) as TotalVotesCast
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    group by u.Id
), ComplexFilteredPosts as (
    select p.*
    from Posts p
    where (
        (p.Title is not null and char_length(p.Title) > 20 and (p.Tags like '%<sql>%' or p.Tags like '%<performance>%')) 
        or
        (p.Score > 10 and coalesce(p.FavoriteCount, 0) > 2)
        or
        (p.ClosedDate is null and p.AnswerCount >= (select avg(AnswerCount) from Posts where PostTypeId = 1))
    )
    and p.CreationDate > (timestamp '2024-10-01 12:34:56') - interval '5 years'
)
select 
    q.Id as QuestionId,
    q.Title,
    q.CreationDate,
    u.DisplayName as OwnerName,
    u.Reputation,
    b_g.BadgeCount as GoldBadges,
    b_s.BadgeCount as SilverBadges,
    b_b.BadgeCount as BronzeBadges,
    qa.AnswerCount,
    qa.MaxAnswerScore,
    qa.DuplicateCount,
    ps.ScoreRank,
    v.UpVotesReceived,
    v.DownVotesReceived,
    v.CloseVotesCast,
    tpa.AnswersGiven as UserAnswersGiven,
    tpa.AvgAnswerScore as UserAvgAnswerScore,
    row_number() over (order by qa.AnswerCount desc, q.Score desc) as PopularityRank,
    case 
        when q.ClosedDate is not null then 'Closed'
        when qa.DuplicateCount > 0 then 'Duplicate'
        else 'Open'
    end as PostStatus,
    substring(coalesce(q.Tags, '') from 1 for 80) as TagSnippet,
    (select count(*) 
     from Comments c 
     where c.PostId = q.Id 
       and c.CreationDate > (timestamp '2024-10-01 12:34:56') - interval '1 year'
       and (lower(c.Text) like '%performance%' or lower(c.Text) like '%sql%')
    ) as RecentCommentCount
from Posts q
left join Users u on u.Id = q.OwnerUserId
left join BadgeSummary b_g on b_g.UserId = u.Id and b_g.Class = 1
left join BadgeSummary b_s on b_s.UserId = u.Id and b_s.Class = 2
left join BadgeSummary b_b on b_b.UserId = u.Id and b_b.Class = 3
left join QuestionAnswerStats qa on qa.QuestionId = q.Id
left join PostScoreRankings ps on ps.Id = q.Id
left join UserVoteImpact v on v.UserId = u.Id
left join TopAnswerers tpa on tpa.OwnerUserId = u.Id
where q.PostTypeId = 1
  and exists (select 1 from RecursivePostRelations r where r.RootPostId = q.Id and r.CurrentPostId = q.Id and r.Depth = 0)
  and q.Id in (select Id from ComplexFilteredPosts)
order by PopularityRank, q.CreationDate desc
limit 100;