-- {"query": "970.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1319} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.Score, 0) as TopPostScore,
        p.Id as TopPostId
    from Tags t
    left join Posts p on p.Id = t.WikiPostId and p.PostTypeId = 5
    where t.IsModeratorOnly = 0

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        case when r.TopPostScore > coalesce(p.Score,0) then r.TopPostScore else coalesce(p.Score,0) end,
        case when r.TopPostScore > coalesce(p.Score,0) then r.TopPostId else p.Id end
    from Tags t
    join RecursiveTagHierarchy r on t.Id = r.Id
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 4
    where t.IsRequired = 0
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswerCount,
        sum(coalesce(p.Score,0)) as TotalScore,
        sum(case when c.Id is not null then 1 else 0 end) as CommentCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
AcceptedAnswerRanks as (
    select
        p.Id as QuestionId,
        p.AcceptedAnswerId,
        p.Title,
        p.Score as QuestionScore,
        a.Score as AcceptedAnswerScore,
        u.DisplayName as OwnerUser,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as UserQuestionRank
    from Posts p
    left join Posts a on a.Id = p.AcceptedAnswerId
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 and p.AcceptedAnswerId is not null
),
UserTopQuestions as (
    select
        aar.*,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.TotalScore,
        ua.CommentCount
    from AcceptedAnswerRanks aar
    join UserActivity ua on ua.UserId = aar.OwnerUser
    where aar.UserQuestionRank <= 5
),
DuplicateLinksCTE as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate
    from PostLinks pl
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
HotUsers as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.TotalScore,
        ua.CommentCount,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        dense_rank() over (order by ua.Reputation desc, GoldBadges desc, SilverBadges desc) as ReputationRank
    from UserActivity ua
    left join Badges b on b.UserId = ua.UserId
    group by ua.UserId, ua.DisplayName, ua.Reputation, ua.QuestionCount, ua.AnswerCount, ua.TotalScore, ua.CommentCount
),
UserCommentsRanking as (
    select
        c.UserId,
        u.DisplayName,
        count(c.Id) as CommentsMade,
        row_number() over (partition by c.UserId order by c.CreationDate desc) as RecentCommentRowNum
    from Comments c
    left join Users u on u.Id = c.UserId
    where c.UserId is not null
    group by c.UserId, u.DisplayName
)
select 
    h.DisplayName,
    h.Reputation,
    h.QuestionCount,
    h.AnswerCount,
    h.TotalScore,
    h.CommentCount,
    h.GoldBadges,
    h.SilverBadges,
    h.BronzeBadges,
    array_agg(distinct dt.TagName order by dt.Count desc) filter (where dt.TagName is not null) as TagsExplored,
    coalesce(uc.CommentsMade,0) as TotalComments,
    coalesce(dl.DuplicateLinksCount,0) as DuplicateQuestionLinks,
    row_number() over (order by h.Reputation desc) as OverallRank
from HotUsers h
left join UserCommentsRanking uc on uc.UserId = h.UserId
left join (
    select 
        pl.PostId,
        count(*) as DuplicateLinksCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
) dl on dl.PostId = any (
    select Id from Posts where OwnerUserId = h.UserId
)
left join RecursiveTagHierarchy dt on dt.Id in (
    select distinct unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'))::int
    from Posts p
    where p.OwnerUserId = h.UserId and p.PostTypeId = 1 and p.Tags is not null
)
group by h.DisplayName, h.Reputation, h.QuestionCount, h.AnswerCount, h.TotalScore, h.CommentCount, h.GoldBadges, h.SilverBadges, h.BronzeBadges, uc.CommentsMade, dl.DuplicateLinksCount
having h.Reputation > 1000 and h.GoldBadges >= 1
order by OverallRank
limit 20;