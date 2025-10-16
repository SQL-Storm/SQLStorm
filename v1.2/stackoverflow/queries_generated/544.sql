-- {"query": "544.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1470} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> r.Id and t.Count < r.Count and not t.TagName = any(r.Path)
    where r.Level < 3
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        coalesce(sum(vb.BountyAmount),0) as TotalBountyGiven,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes vb on vb.UserId = u.Id and vb.VoteTypeId = 8 -- BountyStart
    group by u.Id, u.DisplayName
),
PostWithComments as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.Title,
        p.AcceptedAnswerId,
        p.ParentId,
        p.ClosedDate,
        cmt.CommentCount,
        cmt.MaxCommentScore,
        cmt.MaxCommentText,
        row_number() over (partition by p.Id order by p.Score desc) as rn
    from Posts p
    left join (
        select
            PostId,
            count(*) as CommentCount,
            max(Score) as MaxCommentScore,
            max(Text) filter (where Score = (select max(Score) from Comments c2 where c2.PostId = c.PostId)) as MaxCommentText
        from Comments c
        group by PostId
    ) cmt on cmt.PostId = p.Id
    where p.PostTypeId in (1,2)
),
AcceptedAnswerStats as (
    select
        p.AcceptedAnswerId as AnswerId,
        count(*) as AcceptedCount,
        avg(p.Score) as AvgQuestionScore
    from Posts p
    where p.AcceptedAnswerId is not null
    group by p.AcceptedAnswerId
),
UserBadgeSummary as (
    select
        b.UserId,
        count(*) as TotalBadges,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Name) as DistinctBadgeNames,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
ComplexPostMetrics as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ClosedDate,
        p.CommentCount,
        p.FavoriteCount,
        case 
            when p.ClosedDate is not null then 'Closed'
            when p.AcceptedAnswerId is not null then 'Answered'
            else 'Open'
        end as PostStatus,
        length(p.Body) as BodyLength,
        coalesce(array_length(string_to_array(trim(both '<>' from p.Tags), '><'),1),0) as TagCount,
        (select count(*) from PostLinks pl where pl.PostId = p.Id and pl.LinkTypeId = 3) as DuplicateLinksCount,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as UserPostRankByScore
    from Posts p
    where p.PostTypeId = 1
)
select
    u.Id as UserId,
    u.DisplayName,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.TotalBountyGiven,
    ua.AvgPostScore,
    coalesce(ubs.TotalBadges,0) as TotalBadges,
    coalesce(ubs.GoldBadges,0) as GoldBadges,
    coalesce(ubs.SilverBadges,0) as SilverBadges,
    coalesce(ubs.BronzeBadges,0) as BronzeBadges,
    max(p.CreationDate) as LastQuestionDate,
    min(p.CreationDate) as FirstQuestionDate,
    count(distinct p.Id) as TotalQuestions,
    avg(p.Score) as AvgQuestionScore,
    avg(p.ViewCount) as AvgQuestionViews,
    sum(case when p.PostStatus = 'Closed' then 1 else 0 end) as ClosedQuestions,
    sum(case when p.PostStatus = 'Answered' then 1 else 0 end) as AnsweredQuestions,
    max(p.DuplicateLinksCount) as MaxDuplicateLinks,
    max(p.UserPostRankByScore) as MaxUserPostRank,
    string_agg(distinct t.TagName, ', ') filter (where t.TagName is not null) as UserTagsUsed,
    count(distinct c.Id) as TotalCommentsMade,
    max(c.CreationDate) as LastCommentDate,
    sum(case when c.Text ilike '%performance%' then 1 else 0 end) as CommentsMentioningPerformance
from Users u
left join UserActivity ua on ua.UserId = u.Id
left join UserBadgeSummary ubs on ubs.UserId = u.Id
left join ComplexPostMetrics p on p.OwnerUserId = u.Id
left join Comments c on c.UserId = u.Id
left join Posts pt on pt.Id = c.PostId and pt.PostTypeId = 1
left join LATERAL (
    select distinct unnest(string_to_array(trim(both '<>' from p.Tags), '><')) as TagName
    from Posts p2 where p2.OwnerUserId = u.Id and p2.PostTypeId = 1 limit 10
) t on true
where u.Reputation > 1000
group by u.Id, u.DisplayName, ua.QuestionsPosted, ua.AnswersPosted, ua.TotalBountyGiven, ua.AvgPostScore, ubs.TotalBadges, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges
having count(distinct p.Id) > 5
order by AvgQuestionScore desc, ClosedQuestions asc
limit 50;