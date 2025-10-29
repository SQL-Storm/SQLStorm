-- {"query": "2143.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1572}
with RecursiveTagPosts as (
    select
        t.Id as TagId,
        t.TagName,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId
    from Tags t
    join Posts p on p.Tags like '%' || '<' || t.TagName || '>' || '%'
    where p.PostTypeId = 1
), LatestUserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.WebsiteUrl,
        row_number() over (partition by u.Id order by u.LastAccessDate desc) as rn
    from Users u
), TopUserBadges as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by b.UserId order by b.Class, b.Date desc) as rn
    from Badges b
), QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.OwnerUserId,
        count(a.Id) filter (where a.PostTypeId = 2) as TotalAnswers,
        sum(a.Score) filter (where a.PostTypeId = 2) as TotalAnswerScore,
        max(a.Score) filter (where a.PostTypeId = 2) as MaxAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.OwnerUserId
), CloseVotesCTE as (
    select
        ph.PostId,
        count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseVotes,
        count(case when ph.PostHistoryTypeId = 11 then 1 end) as ReopenVotes
    from PostHistory ph
    group by ph.PostId
), UserCommentCounts as (
    select
        c.UserId,
        count(*) as CommentCount
    from Comments c
    where c.UserId is not null
    group by c.UserId
), PostLinkDupes as (
    select
        pl.PostId,
        count(case when lt.Name = 'Duplicate' then 1 end) as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
), UserScoreRankings as (
    select
        p.OwnerUserId,
        sum(p.Score) as TotalPostScore,
        rank() over (order by sum(p.Score) desc) as UserScoreRank
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
), HighActivityPosts as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        dense_rank() over (order by p.ViewCount desc, p.Score desc) as PopularityRank
    from Posts p
    where p.PostTypeId = 1 and p.ClosedDate is null
), AcceptedAnswerDetails as (
    select
        p.Id as QuestionId,
        aa.Id as AcceptedAnswerId,
        aa.Score as AcceptedAnswerScore,
        aa.OwnerUserId as AcceptedAnswerOwner
    from Posts p
    left join Posts aa on aa.Id = p.AcceptedAnswerId
    where p.PostTypeId = 1
)
select 
    q.Id as QuestionId,
    q.Title,
    q.Tags,
    q.CreationDate,
    q.Score as QuestionScore,
    q.ViewCount,
    qa.TotalAnswers,
    qa.TotalAnswerScore,
    qa.MaxAnswerScore,
    coalesce(cv.CloseVotes, 0) as CloseVotes,
    coalesce(cv.ReopenVotes, 0) as ReopenVotes,
    coalesce(pl.DuplicateCount, 0) as DuplicateLinks,
    u.DisplayName as QuestionOwner,
    u.Reputation as OwnerReputation,
    u.Location as OwnerLocation,
    u.WebsiteUrl as OwnerWebsite,
    uc.CommentCount as OwnerCommentCount,
    b2.CreatedBadgeName,
    aa.AcceptedAnswerId,
    aa.AcceptedAnswerScore,
    aa.AcceptedAnswerOwner,
    au.DisplayName as AcceptedAnswerOwnerName,
    uscore.UserScoreRank,
    hap.PopularityRank,
    case
        when q.ClosedDate is not null then 'Closed'
        when qa.TotalAnswers > 10 and q.ViewCount > 10000 then 'Hot'
        else 'Normal'
    end as PostStatus,
    (
        select string_agg(distinct phType.Name, ', ' order by phType.Name)
        from PostHistory ph
        join PostHistoryTypes phType on phType.Id = ph.PostHistoryTypeId
        where ph.PostId = q.Id
          and ph.UserId = q.OwnerUserId
          and ph.CreationDate between q.CreationDate and q.CreationDate + interval '30' day
    ) as RecentUserPostHistoryTypes,
    length(trim(coalesce(q.Body, ''))) as BodyLength,
    length(coalesce(regexp_replace(q.Tags, '[^a-zA-Z0-9]', '', 'g'), '')) as TagAlphaNumLength,
    case 
        when u.WebsiteUrl is not null and position('https://' in u.WebsiteUrl) = 1 then substring(u.WebsiteUrl from 9)
        when u.WebsiteUrl is not null and position('http://' in u.WebsiteUrl) = 1 then substring(u.WebsiteUrl from 8)
        else u.WebsiteUrl
    end as NormalizedWebsiteUrl,
    case
        when q.Title is null then 'No Title'
        when q.Title = '' then 'Empty Title'
        else q.Title
    end as NormalizedTitle,
    case 
        when u.Location is null then 'Unknown'
        else u.Location
    end as LocationLabel
from Posts q
left join QuestionAnswerStats qa on qa.QuestionId = q.Id
left join CloseVotesCTE cv on cv.PostId = q.Id
left join PostLinkDupes pl on pl.PostId = q.Id
left join Users u on u.Id = q.OwnerUserId
left join UserCommentCounts uc on uc.UserId = u.Id
left join (
    select UserId, BadgeNameCreated as CreatedBadgeName from (
        select b.UserId, b.Name as BadgeNameCreated, row_number() over (partition by b.UserId order by b.Class) as brnk
        from Badges b
    ) t where brnk = 1
) b2 on b2.UserId = u.Id
left join AcceptedAnswerDetails aa on aa.QuestionId = q.Id
left join Users au on au.Id = aa.AcceptedAnswerOwner
left join UserScoreRankings uscore on uscore.OwnerUserId = u.Id
left join HighActivityPosts hap on hap.Id = q.Id
where q.PostTypeId = 1
  and q.CreationDate > (cast('2024-10-01' as date) - interval '1' year)
  and exists (
    select 1 
    from PostHistory ph2
    where ph2.PostId = q.Id
      and ph2.PostHistoryTypeId in (4,5,6)
      and ph2.CreationDate > (q.CreationDate + interval '7' day)
)
group by
    q.Id,
    q.Title,
    q.Tags,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    qa.TotalAnswers,
    qa.TotalAnswerScore,
    qa.MaxAnswerScore,
    cv.CloseVotes,
    cv.ReopenVotes,
    pl.DuplicateCount,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.WebsiteUrl,
    uc.CommentCount,
    b2.CreatedBadgeName,
    aa.AcceptedAnswerId,
    aa.AcceptedAnswerScore,
    aa.AcceptedAnswerOwner,
    au.DisplayName,
    uscore.UserScoreRank,
    hap.PopularityRank,
    q.ClosedDate,
    q.Body,
    q.Id -- ensure PostHistory correlated column OwnerUserId usage covered by grouping via q.Id
order by hap.PopularityRank asc NULLS LAST, q.Score desc
limit 100;