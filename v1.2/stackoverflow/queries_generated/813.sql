-- {"query": "813.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1357} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswerCount,
        count(distinct b.Id) as BadgeCount,
        sum(vt.Name = 'UpMod'::text)::int as TotalUpVotes,
        sum(vt.Name = 'DownMod'::text)::int as TotalDownVotes,
        row_number() over (partition by u.Id order by p.CreationDate desc nulls last) as RecentPostRank
    from 
        Users u
        left join Posts p on p.OwnerUserId = u.Id
        left join Posts p2 on p2.OwnerUserId = u.Id
        left join Badges b on b.UserId = u.Id
        left join Votes v on v.UserId = u.Id
        left join VoteTypes vt on vt.Id = v.VoteTypeId
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
), RecentQuestions as (
    select 
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(a.AnswerCount,0) as AnswerCount,
        coalesce(acc.Score, 0) as AcceptedAnswerScore,
        case 
            when p.ClosedDate is not null then 'Closed'
            when p.AcceptedAnswerId is not null then 'Accepted'
            else 'Open'
        end as PostStatus
    from 
        Posts p
        left join (
            select ParentId, count(*) as AnswerCount from Posts where PostTypeId = 2 group by ParentId
        ) a on a.ParentId = p.Id
        left join Posts acc on acc.Id = p.AcceptedAnswerId
    where p.PostTypeId = 1
), QuestionTagsExploded as (
    select 
        q.Id as QuestionId, 
        unnest(string_to_array(substring(q.Tags from 2 for length(q.Tags)-2), '><')) as Tag
    from RecentQuestions q
    where q.Tags is not null
), TagPopularity as (
    select 
        Tag,
        count(distinct QuestionId) as QuestionCount,
        sum(Score) as TotalScore,
        avg(ViewCount) as AvgViewCount,
        max(Score) as MaxScore
    from QuestionTagsExploded qte
    join RecentQuestions rq on rq.Id = qte.QuestionId
    group by Tag
), UserBadgeWindow as (
    select 
        b.UserId,
        b.Name,
        b.Class,
        b.Date,
        rank() over (partition by b.UserId order by b.Date desc) as BadgeRank
    from Badges b
    where b.Class = 1
), HighRepUsersWithGoldBadges as (
    select 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.BadgeCount,
        coalesce(sum(case when ubw.BadgeRank <= 3 then 1 else 0 end),0) as Top3GoldBadges
    from RecursiveUserActivity ua
    left join UserBadgeWindow ubw on ubw.UserId = ua.UserId
    where ua.Reputation > 10000
    group by ua.UserId, ua.DisplayName, ua.Reputation, ua.QuestionCount, ua.AnswerCount, ua.BadgeCount
), DuplicateLinkedQuestions as (
    select distinct 
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        p1.Title as DuplicateTitle,
        p2.Title as OriginalTitle,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
), UserRecentComments as (
    select 
        c.UserId,
        c.PostId,
        c.CreationDate,
        c.Text,
        rank() over (partition by c.UserId order by c.CreationDate desc) as RecentCommentRank
    from Comments c
    where c.UserId is not null
), UserCommentStats as (
    select 
        u.Id as UserId,
        count(distinct c.Id) as TotalComments,
        count(distinct case when c.CreationDate > now() - interval '30 days' then c.Id end) as RecentMonthComments
    from Users u
    left join Comments c on c.UserId = u.Id
    group by u.Id
)
select 
    hru.UserId,
    hru.DisplayName,
    hru.Reputation,
    hru.QuestionCount,
    hru.AnswerCount,
    hru.BadgeCount,
    hru.Top3GoldBadges,
    tp.Tag,
    tp.QuestionCount as TagQuestionCount,
    tp.TotalScore as TagTotalScore,
    tp.AvgViewCount as TagAvgViewCount,
    tp.MaxScore as TagMaxScore,
    dq.DuplicateQuestionId,
    dq.OriginalQuestionId,
    dq.DuplicateTitle,
    dq.OriginalTitle,
    dq.LinkCreationDate,
    ucs.TotalComments,
    ucs.RecentMonthComments
from HighRepUsersWithGoldBadges hru
left join QuestionTagsExploded qte on qte.QuestionId in (
    select Id from Posts where OwnerUserId = hru.UserId and PostTypeId = 1
)
left join TagPopularity tp on tp.Tag = qte.Tag
left join DuplicateLinkedQuestions dq on dq.DuplicateQuestionId in (
    select Id from Posts where OwnerUserId = hru.UserId and PostTypeId = 1
)
left join UserCommentStats ucs on ucs.UserId = hru.UserId
where tp.QuestionCount > 10 or tp.QuestionCount is null
order by hru.Reputation desc, tp.TotalScore desc nulls last, dq.LinkCreationDate desc nulls last
limit 50;