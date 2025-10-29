-- {"query": "2802.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1380} 
with UserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        count(b.Id) as TotalBadges,
        row_number() over (partition by u.Id order by b.Date desc) as LastBadgeRank,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
TopPosts as (
    select 
        p.Id, p.OwnerUserId, p.PostTypeId, p.Score, p.ViewCount, p.CreationDate, p.Title,
        coalesce(pl.RelatedPostId, 0) as RelatedPostId,
        pl.LinkTypeId,
        row_number() over (
            partition by p.OwnerUserId 
            order by p.Score desc, p.ViewCount desc, p.CreationDate
        ) as PostRank
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 1 -- Linked posts only
    where p.PostTypeId in (1, 2) -- Questions and Answers only
),
UserActivity as (
    select 
        u.Id as UserId,
        count(distinct ph.Id) as HistoryEdits,
        count(distinct c.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesGiven,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesGiven,
        sum(case when v.VoteTypeId in (8, 9) then coalesce(v.BountyAmount, 0) else 0 end) as TotalBountiesGiven,
        avg(p.Score) filter (where p.PostTypeId=1) as AvgQuestionScore,
        avg(p.Score) filter (where p.PostTypeId=2) as AvgAnswerScore,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id
),
FilteredPosts as (
    select 
        p.Id, p.OwnerUserId, p.Title, p.Tags, p.Score, p.ViewCount, p.CreationDate, p.AcceptedAnswerId,
        (select count(*) from Comments c2 where c2.PostId = p.Id) as CommentNum,
        (select count(*) from Votes v2 where v2.PostId = p.Id and v2.VoteTypeId = 2) as UpVotesCount,
        (select count(*) from Votes v2 where v2.PostId = p.Id and v2.VoteTypeId = 3) as DownVotesCount
    from Posts p
    where p.PostTypeId = 1 -- Questions only
    and p.Score > 10
    and p.ViewCount > 1000
    and p.AcceptedAnswerId is not null
),
QuestionsWithCloseInfo as (
    select 
        fp.*,
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        (select count(distinct ph2.UserId) from PostHistory ph2 where ph2.PostId = fp.Id and ph2.PostHistoryTypeId = 10) as CloseVoterCount
    from FilteredPosts fp
    left join PostHistory ph on ph.PostId = fp.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id::varchar = ph.Comment
),
FinalRanking as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        u.DisplayName,
        q.Score,
        q.ViewCount,
        q.CommentNum,
        q.UpVotesCount,
        q.DownVotesCount,
        q.AcceptedAnswerId,
        q.CloseReasonName,
        q.CloseVoterCount,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ua.HistoryEdits,
        ua.CommentCount as UserComments,
        ua.UpVotesGiven,
        ua.DownVotesGiven,
        ua.TotalBountiesGiven,
        ua.AvgQuestionScore,
        ua.AvgAnswerScore,
        ua.LastPostDate,
        row_number() over (
            order by 
            q.Score * 0.5 + q.ViewCount * 0.2 + ub.GoldBadges * 2 + ua.HistoryEdits * 1.5 desc,
            q.CommentNum desc
        ) as RankValue
    from QuestionsWithCloseInfo q
    left join Users u on u.Id = q.OwnerUserId
    left join UserBadgeCounts ub on ub.UserId = q.OwnerUserId
    left join UserActivity ua on ua.UserId = q.OwnerUserId
)
select 
    fr.RankValue,
    fr.QuestionId,
    fr.Title,
    fr.DisplayName as OwnerName,
    fr.Score,
    fr.ViewCount,
    fr.CommentNum,
    fr.UpVotesCount,
    fr.DownVotesCount,
    fr.AcceptedAnswerId,
    coalesce(fr.CloseReasonName, 'Open') as CloseReason,
    fr.CloseVoterCount,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.HistoryEdits,
    fr.UserComments,
    fr.UpVotesGiven,
    fr.DownVotesGiven,
    fr.TotalBountiesGiven,
    round(fr.AvgQuestionScore::numeric,2) as AvgQuestionScore,
    round(fr.AvgAnswerScore::numeric,2) as AvgAnswerScore,
    fr.LastPostDate,
    case when lower(fr.Title) like '%sql%' or lower(fr.Title) like '%database%' then true else false end as MentionsSQLOrDatabase,
    case when fr.CommentNum > 10 and fr.Score > 50 then 'High Engagement'
         when fr.CommentNum between 5 and 10 then 'Medium Engagement'
         else 'Low Engagement' end as EngagementLevel
from FinalRanking fr
where fr.RankValue <= 100
order by fr.RankValue;