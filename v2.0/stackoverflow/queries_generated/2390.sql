-- {"query": "2390.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2084} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(u.Views,0) as Views,
        coalesce(u.UpVotes,0) as UpVotes,
        coalesce(u.DownVotes,0) as DownVotes,
        cast(0 as int) as TotalAnswers,
        cast(0 as int) as TotalQuestions,
        cast(0 as int) as TotalComments,
        cast(0 as int) as TotalBadges,
        cast(0 as int) as TotalVotesCast,
        u.LastAccessDate,
        1 as level
    from Users u
    where u.Reputation > 1000

    union all

    select
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.CreationDate,
        r.Location,
        r.Views,
        r.UpVotes,
        r.DownVotes,
        r.TotalAnswers + coalesce(pa.Answers,0),
        r.TotalQuestions + coalesce(pq.Questions,0),
        r.TotalComments + coalesce(pc.Comments,0),
        r.TotalBadges + coalesce(pb.Badges,0),
        r.TotalVotesCast + coalesce(pv.Votes,0),
        greatest(r.LastAccessDate, coalesce(pq.LatestActivity, r.LastAccessDate)) as LastAccessDate,
        r.level + 1
    from RecursiveUserActivity r
    left join (
        select OwnerUserId, count(*) as Answers
        from Posts
        where PostTypeId = 2
        group by OwnerUserId
    ) pa on pa.OwnerUserId = r.UserId
    left join (
        select OwnerUserId, count(*) as Questions, max(LastActivityDate) as LatestActivity
        from Posts
        where PostTypeId = 1
        group by OwnerUserId
    ) pq on pq.OwnerUserId = r.UserId
    left join (
        select UserId, count(*) as Comments
        from Comments
        group by UserId
    ) pc on pc.UserId = r.UserId
    left join (
        select UserId, count(*) as Badges
        from Badges
        group by UserId
    ) pb on pb.UserId = r.UserId
    left join (
        select UserId, count(*) as Votes
        from Votes
        group by UserId
    ) pv on pv.UserId = r.UserId
    where r.level < 1
),
QuestionAnswers AS (
    select
        q.Id QuestionId,
        q.Title QuestionTitle,
        q.CreationDate QuestionCreation,
        q.ViewCount QuestionViews,
        q.Score QuestionScore,
        q.AnswerCount,
        q.Tags QuestionTags,
        a.Id AnswerId,
        a.CreationDate AnswerCreation,
        a.Score AnswerScore,
        a.OwnerUserId AnswerOwnerUserId,
        a.ParentId AnswerParentId
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
RankedAnswers AS (
    select
        qa.*,
        row_number() over (partition by qa.QuestionId order by qa.AnswerScore desc, qa.AnswerCreation asc) as AnswerRank
    from QuestionAnswers qa
),
AcceptedOrTopAnswer AS (
    select
        r.QuestionId,
        r.QuestionTitle,
        r.QuestionCreation,
        r.QuestionViews,
        r.QuestionScore,
        r.AnswerCount,
        r.QuestionTags,
        r.AnswerId,
        r.AnswerCreation,
        r.AnswerScore,
        coalesce(p.AcceptedAnswerId, r.AnswerId) as SelectedAnswerId,
        r.AnswerOwnerUserId
    from RankedAnswers r
    join Posts p on p.Id = r.QuestionId
    where r.AnswerRank = 1
),
PostLinkAggregates AS (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedCount,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
UserBadgeSummary AS (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges
    from Badges b
    group by b.UserId
),
TopUsersWindow AS (
    select
        u.Id UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.LastAccessDate,
        u.Location,
        coalesce(bs.GoldBadges,0) as GoldBadges,
        coalesce(bs.SilverBadges,0) as SilverBadges,
        coalesce(bs.BronzeBadges,0) as BronzeBadges,
        coalesce(bs.TotalBadges,0) as TotalBadges,
        coalesce(bs.TagBasedBadges,0) as TagBasedBadges,
        rank() over (order by u.Reputation desc, u.Views desc) as ReputationRank
    from Users u
    left join UserBadgeSummary bs on bs.UserId = u.Id
    where u.Reputation > 500
),
FinalSelection AS (
    select
        t.UserId,
        t.DisplayName,
        t.Reputation,
        t.Views,
        t.UpVotes,
        t.DownVotes,
        t.GoldBadges,
        t.SilverBadges,
        t.BronzeBadges,
        t.TotalBadges,
        t.TagBasedBadges,
        t.LastAccessDate,
        t.Location,
        count(distinct p.Id) as QuestionsAsked,
        count(distinct a.Id) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        coalesce(pl.LinkedCount,0) as TotalPostLinks,
        coalesce(pl.DuplicateCount,0) as TotalPostDuplicates,
        max(ph.CreationDate) as LastPostHistoryDate,
        min(ph.CreationDate) as FirstPostHistoryDate,
        avg(p.Score) as AvgQuestionScore,
        avg(a.Score) as AvgAnswerScore,
        max(v.CreationDate) as LastVoteDate,
        sum(case when v.VoteTypeId=2 then 1 else 0 end) as UpVotesCast,
        sum(case when v.VoteTypeId=3 then 1 else 0 end) as DownVotesCast
    from TopUsersWindow t
    left join Posts p on p.OwnerUserId = t.UserId and p.PostTypeId = 1
    left join Posts a on a.OwnerUserId = t.UserId and a.PostTypeId = 2
    left join Comments c on c.UserId = t.UserId
    left join PostLinks pl on pl.PostId = p.Id
    left join PostHistory ph on ph.UserId = t.UserId
    left join Votes v on v.UserId = t.UserId
    group by t.UserId, t.DisplayName, t.Reputation, t.Views, t.UpVotes, t.DownVotes, t.GoldBadges, t.SilverBadges, t.BronzeBadges,
             t.TotalBadges, t.TagBasedBadges, t.LastAccessDate, t.Location, coalesce(pl.LinkedCount,0), coalesce(pl.DuplicateCount,0)
),
FilteredUsers as (
    select *
    from FinalSelection
    where QuestionsAsked > 10 and AnswersGiven > 20 and TotalBadges > 5
)
select
    fu.UserId,
    fu.DisplayName,
    fu.Reputation,
    fu.Views,
    fu.UpVotes,
    fu.DownVotes,
    fu.GoldBadges,
    fu.SilverBadges,
    fu.BronzeBadges,
    fu.TotalBadges,
    fu.TagBasedBadges,
    fu.LastAccessDate,
    fu.Location,
    fu.QuestionsAsked,
    fu.AnswersGiven,
    fu.CommentsMade,
    fu.TotalPostLinks,
    fu.TotalPostDuplicates,
    fu.LastPostHistoryDate,
    fu.FirstPostHistoryDate,
    round(fu.AvgQuestionScore::numeric,2) as AvgQuestionScore,
    round(fu.AvgAnswerScore::numeric,2) as AvgAnswerScore,
    fu.LastVoteDate,
    fu.UpVotesCast,
    fu.DownVotesCast,
    concat(
        case when fu.Reputation > 20000 then 'Legendary'
             when fu.Reputation > 10000 then 'Expert'
             when fu.Reputation > 5000 then 'Advanced'
             else 'Intermediate' end,
        ' | ',
        case when fu.TotalBadges > 50 then 'Badge Hoarder'
             when fu.TotalBadges > 20 then 'Badge Collector'
             else 'Badge Novice' end
    ) as UserStatus,
    case 
        when fu.Location is null then 'Unknown'
        when lower(fu.Location) like '%usa%' then 'USA'
        when lower(fu.Location) like '%india%' then 'India'
        when lower(fu.Location) like '%uk%' or lower(fu.Location) like '%england%' then 'UK'
        else 'Other'
    end as UserRegion
from FilteredUsers fu
order by fu.Reputation desc, fu.TotalBadges desc
limit 100;