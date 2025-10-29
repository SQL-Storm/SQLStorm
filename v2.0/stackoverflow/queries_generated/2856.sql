-- {"query": "2856.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1610} 
with UserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadgesCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount,
        coalesce(q.AnswerCount, 0) as AnswerCount,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwner,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreation,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
TopAnswersWithRankedComments as (
    select
        a.QuestionId,
        a.AnswerId,
        a.AnswerOwner,
        a.AnswerScore,
        a.AnswerCreation,
        c.Id as CommentId,
        c.UserId as CommentUserId,
        c.CreationDate as CommentCreationDate,
        c.Score as CommentScore,
        row_number() over (partition by a.AnswerId order by c.Score desc, c.CreationDate asc) as CommentRank
    from QuestionsWithAnswers a
    left join Comments c on c.PostId = a.AnswerId
    where a.AnswerRank <= 3
),
UserReputationWithRank as (
    select
        Id,
        DisplayName,
        Reputation,
        CreationDate,
        row_number() over (order by Reputation desc, CreationDate asc) as RepRank
    from Users
),
AggregatedPostHistoryEdits as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        count(*) as TotalEdits,
        max(ph.CreationDate) as LastEditDate,
        bool_or(ph.PostHistoryTypeId in (10,11)) as HasCloseOrReopenEvents
    from PostHistory ph
    group by ph.PostId, ph.PostHistoryTypeId
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.Id as UserId,
        u.DisplayName
    from PostLinks pl
    inner join LinkTypes lt on pl.LinkTypeId = lt.Id and lt.Name = 'Duplicate'
    left join Posts p on p.Id = pl.PostId
    left join Users u on u.Id = p.OwnerUserId
),
ComplexUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end), 0) as TotalUpVotes,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end), 0) as TotalDownVotes,
        coalesce(max(p.CreationDate), u.CreationDate) as LastPostDate,
        coalesce(min(ph.CreationDate), u.CreationDate) as FirstEditDate,
        count(distinct ph.PostId) as EditedPostsCount,
        max(case when u.WebsiteUrl is not null and u.WebsiteUrl != '' then 1 else 0 end) as HasWebsite,
        case
            when u.Location is null or trim(u.Location) = '' then 'Unknown'
            else u.Location
        end as UserLocation
    from Users u
    left join Votes v on v.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.CreationDate, u.WebsiteUrl, u.Location
)
select
    u.UserId,
    u.DisplayName,
    u.Location as UserLocation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TagBasedBadgesCount,
    ua.AnswerCount,
    coalesce(sum(case when ta.CommentRank <= 2 then 1 else 0 end),0) as TopCommentsOnTopAnswers,
    ua.QuestionScore,
    ua.ViewCount,
    ua.QuestionCreation,
    ua.AnswerScore,
    ua.AnswerCreation,
    du.PostId as DuplicateQuestionId,
    du.RelatedPostId as DuplicateOfQuestionId,
    ca.TotalUpVotes,
    ca.TotalDownVotes,
    ca.EditedPostsCount,
    ca.HasWebsite,
    ca.LastPostDate,
    ca.FirstEditDate,
    case
        when aba.TotalEdits is null then 0
        else aba.TotalEdits
    end as TotalPostEdits,
    case
        when aba.HasCloseOrReopenEvents then 'Yes'
        else 'No'
    end as HasCloseOrReopenEvents,
    dense_rank() over (partition by u.Location order by u.Reputation desc NULLS LAST) as RepRankInLocation,
    regexp_replace(coalesce(u.DisplayName, 'Anonymous'), '[aeiou]', '*', 'gi') as MaskedDisplayName
from Users u
inner join UserBadges ub on ub.UserId = u.UserId
left join (
    select
        OwnerUserId,
        count(*) filter (where PostTypeId = 2) as AnswerCount,
        max(Score) as AnswerScore,
        max(CreationDate) as AnswerCreation,
        max(Score) filter (where PostTypeId = 1) as QuestionScore,
        max(ViewCount) as ViewCount,
        max(CreationDate) filter (where PostTypeId = 1) as QuestionCreation
    from Posts
    where OwnerUserId is not null
    group by OwnerUserId
) ua on ua.OwnerUserId = u.UserId
left join TopAnswersWithRankedComments ta on ta.AnswerOwner = u.UserId
left join DuplicateLinks du on du.UserId = u.UserId
left join ComplexUserActivity ca on ca.UserId = u.UserId
left join AggregatedPostHistoryEdits aba on aba.PostId = ua.OwnerUserId and aba.PostHistoryTypeId = 5
where u.Reputation > 1000
  and (ua.AnswerCount > 0 or ub.GoldBadges > 0)
group by
    u.UserId, u.DisplayName, u.Location,
    ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.TagBasedBadgesCount,
    ua.AnswerCount, ua.QuestionScore, ua.ViewCount, ua.QuestionCreation, ua.AnswerScore, ua.AnswerCreation,
    du.PostId, du.RelatedPostId,
    ca.TotalUpVotes, ca.TotalDownVotes, ca.EditedPostsCount, ca.HasWebsite, ca.LastPostDate, ca.FirstEditDate,
    aba.TotalEdits, aba.HasCloseOrReopenEvents, u.Reputation
order by u.Reputation desc, ua.AnswerCount desc
limit 100;