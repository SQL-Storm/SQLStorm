-- {"query": "1173.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1170} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate as PostCreationDate,
        coalesce(p.AcceptedAnswerId, -1) as AcceptedAnswerId,
        row_number() over (partition by u.Id order by p.CreationDate desc) as PostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
FilteredPosts as (
    select * 
    from RecursiveUserActivity
    where PostRank <= 5
),
AcceptedAnswerStats as (
    select
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        p.Score,
        p.ViewCount,
        u.Id as OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        (select count(1) from Comments c where c.PostId = p.Id and c.Score > 3) as HighlyRatedCommentsCount
    from Posts p
    join Users u on u.Id = p.OwnerUserId
    join PostTypes pt on pt.Id = p.PostTypeId
    where pt.Name = 'Answer'
),
QuestionActivityWindow as (
    select
        p.Id as QuestionId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        rank() over (partition by p.Tags order by p.CreationDate desc) as RecentTagRank,
        count(*) over (partition by p.OwnerUserId) as TotalUserQuestions,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) over (partition by p.OwnerUserId) as TotalUpVotesReceived
    from Posts p
    left join Votes v on v.PostId = p.Id
    join PostTypes pt on pt.Id = p.PostTypeId and pt.Name = 'Question'
    where p.Tags is not null and p.Tags like '%<sql>%'
),
DuplicatesAndLinks as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name in ('Duplicate', 'Linked')
),
UserBadgeSummary as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
FinalResult as (
    select 
        f.UserId,
        f.DisplayName,
        f.PostId,
        f.PostTypeId,
        f.Score,
        f.ViewCount,
        f.PostCreationDate,
        a.AnswerId,
        a.Score as AnswerScore,
        a.HighlyRatedCommentsCount,
        q.QuestionId,
        q.Title as QuestionTitle,
        coalesce(q.RecentTagRank, 999) as RecentTagRank,
        q.TotalUserQuestions,
        q.TotalUpVotesReceived,
        d.LinkedPostCount,
        d.DuplicateCount,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalBadges,
        row_number() over (partition by f.UserId order by f.Score desc nulls last) as UserPostScoreRank
    from FilteredPosts f
    left join AcceptedAnswerStats a on f.AcceptedAnswerId = a.AnswerId
    left join QuestionActivityWindow q on q.QuestionId = f.PostId
    left join (
        select 
            dl.PostId,
            sum(case when dl.LinkTypeName = 'Linked' then 1 else 0 end) as LinkedPostCount,
            sum(case when dl.LinkTypeName = 'Duplicate' then 1 else 0 end) as DuplicateCount
        from DuplicatesAndLinks dl
        group by dl.PostId
    ) d on d.PostId = f.PostId
    left join UserBadgeSummary ub on ub.UserId = f.UserId
    where f.PostTypeId in (1, 2) -- questions or answers only
)
select
    UserId,
    DisplayName,
    PostId,
    PostTypeId,
    Score,
    ViewCount,
    PostCreationDate,
    coalesce(AnswerId, -1) as AnswerId,
    AnswerScore,
    HighlyRatedCommentsCount,
    QuestionId,
    QuestionTitle,
    RecentTagRank,
    TotalUserQuestions,
    TotalUpVotesReceived,
    coalesce(LinkedPostCount, 0) as LinkedPostCount,
    coalesce(DuplicateCount, 0) as DuplicateCount,
    coalesce(GoldBadges, 0) as GoldBadges,
    coalesce(SilverBadges, 0) as SilverBadges,
    coalesce(BronzeBadges, 0) as BronzeBadges,
    TotalBadges,
    UserPostScoreRank
from FinalResult
where 
    (Score > 10 or RecentTagRank <= 3)
    and (GoldBadges + SilverBadges) >= 5
order by UserPostScoreRank asc, Score desc
limit 100;