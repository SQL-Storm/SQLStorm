-- {"query": "2298.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1796} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, 0 as Level
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select t2.Id, t2.TagName, t2.Count, r.Level + 1
    from Tags t2
    join RecursiveTagHierarchy r on t2.Count < r.Count and t2.Id != r.Id
    where r.Level < 2
),
RecentActiveUsers as (
    select u.Id, u.DisplayName, u.Reputation, u.CreationDate,
        row_number() over (partition by u.Location order by u.Reputation desc, u.LastAccessDate desc) as Rnk
    from Users u
    where u.LastAccessDate > current_date - interval '180 days'
      and u.Reputation > 1000
      and u.Location is not null
),
BadgeSummary as (
    select b.UserId, 
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        bool_or(b.TagBased) as HasTagBasedBadge
    from Badges b
    group by b.UserId
),
QuestionStats as (
    select p.Id as QuestionId, p.OwnerUserId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount,
        coalesce(p.FavoriteCount, 0) as FavoriteCount,
        string_agg(distinct ph.Text, ' | ' order by ph.CreationDate desc) filtered by (where ph.PostHistoryTypeId in (4,5,6)) as RecentEdits,
        (select count(*) from Comments c where c.PostId = p.Id and c.CreationDate > p.CreationDate) as CommentCountAfterPost,
        case 
            when p.ClosedDate is not null then 1
            else 0
        end as IsClosed,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        (select coalesce(avg(a.Score), 0) from Posts a where a.ParentId = p.Id and a.PostTypeId = 2) as AvgAnswerScore
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    where p.PostTypeId = 1
),
AnswerDetails as (
    select a.Id as AnswerId, a.ParentId as QuestionId, a.OwnerUserId, a.CreationDate, a.Score,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank,
        (select count(*) from Comments c where c.PostId = a.Id) as CommentCount,
        case when a.Id = q.AcceptedAnswerId then 1 else 0 end as IsAccepted,
        u.Reputation as OwnerReputation
    from Posts a
    left join Posts q on q.Id = a.ParentId
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
UserAggregates as (
    select u.Id as UserId, u.DisplayName, u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct a.Id) filter (where a.PostTypeId = 2) as AnswersGiven,
        coalesce(sum(case when a.Score > 10 then 1 else 0 end), 0) as HighScoreAnswers,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore,
        avg(a.Score) filter (where a.PostTypeId = 2) as AvgAnswerScore,
        coalesce(sum(v.BountyAmount), 0) as TotalBountyReceived,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end), 0) as TotalUpVotes
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join Votes v on v.UserId = u.Id and v.VoteTypeId = 8 -- BountyStart as proxy for bounties received
    group by u.Id
),
ComplexQuestions as (
    select qs.QuestionId, qs.Title, qs.CreationDate, qs.Score, qs.ViewCount, qs.AnswerCount, qs.FavoriteCount,
        qs.RecentEdits, qs.CommentCountAfterPost, qs.IsClosed, qs.UpVotes, qs.DownVotes, qs.AvgAnswerScore,
        array(
            select unnest(string_to_array(coalesce(qs.RecentEdits,''), ' | ')) 
            from generate_series(1,5)
        ) as TopRecentEdits,
        at.UserId as TopAnswerUserId, at.AnswerRank, at.IsAccepted, at.Score as TopAnswerScore,
        u.DisplayName as TopAnswerUserDisplayName, u.Reputation as TopAnswerUserReputation,
        bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges, bs.HasTagBasedBadge
    from QuestionStats qs
    left join AnswerDetails at on at.QuestionId = qs.QuestionId and at.AnswerRank = 1
    left join Users u on u.Id = at.UserId
    left join BadgeSummary bs on bs.UserId = qs.OwnerUserId
    where qs.AnswerCount > 0 and qs.Score >= 5
),
CombinedPosts as (
    select p.Id as PostId, p.Title, p.Tags, p.CreationDate, p.Score, p.ViewCount,
        case when p.PostTypeId = 1 then 'Question'
             when p.PostTypeId = 2 then 'Answer'
             else 'Other'
        end as PostType,
        u.DisplayName as OwnerName,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        (select count(*) from PostLinks pl where pl.PostId = p.Id) as LinksCount,
        row_number() over (partition by p.PostTypeId order by p.Score desc) as ScoreRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1, 2)
      and p.CreationDate > current_date - interval '1 year'
)
select rp.PostId, rp.PostType, rp.Title, rp.Tags,
    rp.CreationDate, rp.Score, rp.ViewCount, rp.CommentCount, rp.UpVotes, rp.DownVotes, rp.LinksCount, rp.ScoreRank,
    cu.QuestionsAsked, cu.AnswersGiven, cu.HighScoreAnswers, cu.MaxQuestionScore, cu.AvgAnswerScore, cu.TotalBountyReceived, cu.TotalUpVotes,
    ct.Level as TagHierarchyLevel,
    ca.TopAnswerUserDisplayName, ca.TopAnswerUserReputation, ca.GoldBadges, ca.SilverBadges, ca.BronzeBadges, ca.HasTagBasedBadge,
    case 
        when rp.ScoreRank <= 10 then 'Top 10'
        when rp.ScoreRank <= 50 then 'Top 50'
        else 'Other'
    end as ScoreCategory,
    case when rp.CommentCount > 10 or rp.UpVotes > rp.DownVotes * 3 then 'High Interaction' else 'Normal' end as InteractionLevel
from CombinedPosts rp
left join UserAggregates cu on cu.UserId = (select OwnerUserId from Posts where Id = rp.PostId)
left join ComplexQuestions ca on ca.QuestionId = rp.PostId and rp.PostType = 'Question'
left join RecursiveTagHierarchy ct on ct.TagName = substring(rp.Tags from '<([^>]+)>')
where rp.CommentCount is not null
order by rp.Score desc, rp.ViewCount desc
limit 100;