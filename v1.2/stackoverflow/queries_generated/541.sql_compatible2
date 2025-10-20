with recursive RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        1 as Level,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate as PostCreationDate,
        ph.Id as LastEditHistoryId,
        ph.CreationDate as LastEditDate,
        row_number() over (partition by u.Id order by p.CreationDate desc) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId in (4,5,6,7,8,9)
    where u.Reputation > 1000

    union all

    select
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.Level + 1,
        p2.Id,
        p2.PostTypeId,
        p2.Score,
        p2.CreationDate,
        ph2.Id,
        ph2.CreationDate,
        row_number() over (partition by rua.UserId order by p2.CreationDate desc)
    from RecursiveUserActivity rua
    join Posts p2 on p2.OwnerUserId = rua.UserId and p2.CreationDate > rua.PostCreationDate
    left join PostHistory ph2 on ph2.PostId = p2.Id and ph2.PostHistoryTypeId in (4,5,6,7,8,9)
    where rua.Level < 3
),
UserBadgeRanks as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    where b.Date > (cast('2024-10-01' as date) - interval '365' day)
    group by b.UserId, b.Class
),
UserPostStats as (
    select
        p.OwnerUserId as UserId,
        count(case when p.PostTypeId = 1 then 1 end) as Questions,
        count(case when p.PostTypeId = 2 then 1 end) as Answers,
        avg(p.Score) as AvgPostScore,
        max(p.Score) as MaxPostScore,
        sum(case when p.AcceptedAnswerId is not null then 1 else 0 end) as AcceptedAnswersCount,
        sum(p.ViewCount) as TotalViews,
        string_agg(distinct regexp_replace(p.Tags, '<([^>]+)>', '\1'), ',' order by regexp_replace(p.Tags, '<([^>]+)>', '\1')) as DistinctTags
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
TopUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ups.Questions,
        ups.Answers,
        ups.AvgPostScore,
        ups.MaxPostScore,
        ups.AcceptedAnswersCount,
        ups.TotalViews,
        ups.DistinctTags
    from Users u
    left join (
        select
            UserId,
            coalesce(max(case when Class = 1 then BadgeCount end),0) as GoldBadges,
            coalesce(max(case when Class = 2 then BadgeCount end),0) as SilverBadges,
            coalesce(max(case when Class = 3 then BadgeCount end),0) as BronzeBadges
        from UserBadgeRanks
        group by UserId
    ) ub on ub.UserId = u.Id
    left join UserPostStats ups on ups.UserId = u.Id
    where u.Reputation > 5000
),
PostLinkSummary as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as RelatedPostsCount,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.DisplayName as Answerer,
        vUp.VoteCount as UpVotes,
        vDown.VoteCount as DownVotes,
        pl.RelatedPostsCount,
        pl.DuplicateCount,
        pl.LinkedCount,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    left join (
        select PostId, count(*) as VoteCount from Votes where VoteTypeId = 2 group by PostId
    ) vUp on vUp.PostId = a.Id
    left join (
        select PostId, count(*) as VoteCount from Votes where VoteTypeId = 3 group by PostId
    ) vDown on vDown.PostId = a.Id
    left join PostLinkSummary pl on pl.PostId = q.Id
    where q.PostTypeId = 1
),
FilteredQuestions as (
    select
        qas.QuestionId,
        qas.Title,
        qas.CreationDate,
        qas.QuestionScore,
        qas.ViewCount,
        max(qas.AnswerScore) as MaxAnswerScore,
        count(distinct qas.AnswerId) as AnswerCount,
        max(qas.UpVotes) as MaxUpVotes,
        max(qas.DownVotes) as MaxDownVotes,
        max(qas.RelatedPostsCount) as RelatedPostsCount,
        max(qas.DuplicateCount) as DuplicateCount,
        max(qas.LinkedCount) as LinkedCount
    from QuestionAnswerStats qas
    group by qas.QuestionId, qas.Title, qas.CreationDate, qas.QuestionScore, qas.ViewCount
    having count(distinct qas.AnswerId) > 3 and max(qas.AnswerScore) > 5
),
FinalResults as (
    select
        tu.Id as UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.GoldBadges,
        tu.SilverBadges,
        tu.BronzeBadges,
        tu.Questions,
        tu.Answers,
        tu.AvgPostScore,
        tu.MaxPostScore,
        tu.AcceptedAnswersCount,
        tu.TotalViews,
        tu.DistinctTags,
        fq.QuestionId,
        fq.Title as QuestionTitle,
        fq.CreationDate as QuestionCreationDate,
        fq.QuestionScore,
        fq.ViewCount as QuestionViews,
        fq.MaxAnswerScore,
        fq.AnswerCount,
        fq.MaxUpVotes,
        fq.MaxDownVotes,
        fq.RelatedPostsCount,
        fq.DuplicateCount,
        fq.LinkedCount,
        case
            when tu.Reputation > 20000 then 'Elite'
            when tu.Reputation > 10000 then 'Pro'
            when tu.Reputation > 5000 then 'Experienced'
            else 'Intermediate'
        end as UserLevel,
        dense_rank() over (order by tu.Reputation desc) as ReputationRank
    from TopUsers tu
    left join Posts p on p.OwnerUserId = tu.Id and p.PostTypeId = 1
    left join FilteredQuestions fq on fq.QuestionId = p.Id
    where fq.QuestionId is not null
)
select
    fr.UserId,
    fr.DisplayName,
    fr.UserLevel,
    fr.Reputation,
    fr.ReputationRank,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.Questions,
    fr.Answers,
    fr.AvgPostScore,
    fr.MaxPostScore,
    fr.AcceptedAnswersCount,
    fr.TotalViews,
    fr.DistinctTags,
    fr.QuestionId,
    fr.QuestionTitle,
    fr.QuestionCreationDate,
    fr.QuestionScore,
    fr.QuestionViews,
    fr.MaxAnswerScore,
    fr.AnswerCount,
    fr.MaxUpVotes,
    fr.MaxDownVotes,
    fr.RelatedPostsCount,
    fr.DuplicateCount,
    fr.LinkedCount
from FinalResults fr
where fr.DuplicateCount < fr.RelatedPostsCount * 0.5
order by fr.ReputationRank, fr.QuestionCreationDate desc
limit 100;