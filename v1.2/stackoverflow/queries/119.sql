-- {"query": "119.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1692} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        count(distinct b.Id) as BadgesEarned,
        row_number() over (partition by u.Id order by ph.CreationDate desc nulls last) as LastEditRank,
        ph.CreationDate as LastEditDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, ph.CreationDate
),
UserLastEdits as (
    select UserId, max(LastEditDate) as LastEditDate
    from RecursiveUserActivity
    group by UserId
),
TopTagsByUser as (
    select
        p.OwnerUserId as UserId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag,
        count(*) as TagCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by p.OwnerUserId, Tag
),
UserTopTagRanks as (
    select
        UserId,
        Tag,
        TagCount,
        rank() over (partition by UserId order by TagCount desc) as TagRank
    from TopTagsByUser
),
UserTopTagsFiltered as (
    select UserId, Tag, TagCount
    from UserTopTagRanks
    where TagRank <= 3
),
PostLinkAggregates as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Linked') as LinkedCount,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        coalesce(pa.AcceptedAnswerScore, 0) as AcceptedAnswerScore,
        coalesce(pa.AcceptedAnswerCreationDate, q.CreationDate) as AcceptedAnswerCreationDate,
        pl.LinkedCount,
        pl.DuplicateCount,
        case when q.ClosedDate is not null then 1 else 0 end as IsClosed,
        (select count(*) from Comments c where c.PostId = q.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 3) as DownVotes
    from Posts q
    left join (
        select
            a.ParentId,
            max(a.Score) filter (where a.Id = q.AcceptedAnswerId) as AcceptedAnswerScore,
            max(a.CreationDate) filter (where a.Id = q.AcceptedAnswerId) as AcceptedAnswerCreationDate
        from Posts a
        join Posts q on q.AcceptedAnswerId = a.Id
        where a.PostTypeId = 2
        group by a.ParentId
    ) pa on pa.ParentId = q.Id
    left join PostLinkAggregates pl on pl.PostId = q.Id
    where q.PostTypeId = 1
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
UserReputationWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        sum(p.Score) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativePostScore,
        count(p.Id) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativePostCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
FinalUserStats as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate,
        ua.LastAccessDate,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.BadgesEarned,
        coalesce(ubs.GoldBadges, 0) as GoldBadges,
        coalesce(ubs.SilverBadges, 0) as SilverBadges,
        coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
        string_agg(distinct utt.Tag, ', ') as TopTags,
        ua.LastEditDate
    from RecursiveUserActivity ua
    left join UserBadgeSummary ubs on ubs.UserId = ua.UserId
    left join UserTopTagsFiltered utt on utt.UserId = ua.UserId
    group by ua.UserId, ua.DisplayName, ua.Reputation, ua.CreationDate, ua.LastAccessDate, ua.QuestionsAsked, ua.AnswersGiven, ua.CommentsMade, ua.BadgesEarned, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ua.LastEditDate
)
select
    fus.UserId,
    fus.DisplayName,
    fus.Reputation,
    fus.CreationDate,
    fus.LastAccessDate,
    fus.QuestionsAsked,
    fus.AnswersGiven,
    fus.CommentsMade,
    fus.BadgesEarned,
    fus.GoldBadges,
    fus.SilverBadges,
    fus.BronzeBadges,
    fus.TopTags,
    fus.LastEditDate,
    qa.QuestionId,
    qa.Title,
    qa.Score as QuestionScore,
    qa.ViewCount,
    qa.AnswerCount,
    qa.AcceptedAnswerScore,
    qa.AcceptedAnswerCreationDate,
    qa.LinkedCount,
    qa.DuplicateCount,
    qa.IsClosed,
    qa.CommentCount,
    qa.UpVotes,
    qa.DownVotes,
    case
        when qa.Score > 100 and qa.ViewCount > 10000 then 'High Impact'
        when qa.Score between 50 and 100 then 'Medium Impact'
        else 'Low Impact'
    end as ImpactCategory,
    concat_ws(' | ',
        'User: ', fus.DisplayName,
        'Reputation: ', fus.Reputation,
        'Top Tags: ', coalesce(fus.TopTags, 'None'),
        'Questions Asked: ', fus.QuestionsAsked,
        'Answers Given: ', fus.AnswersGiven
    ) as UserSummary
from FinalUserStats fus
left join QuestionAnswerStats qa on qa.OwnerUserId = fus.UserId
where fus.Reputation > 1000
  and (qa.IsClosed = 0 or qa.IsClosed is null)
order by fus.Reputation desc, qa.Score desc
limit 100;