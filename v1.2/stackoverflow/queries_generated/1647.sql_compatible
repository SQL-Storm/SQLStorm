with RecursiveUserTags as (
    select
        u.Id as UserId,
        u.DisplayName,
        unnest(string_to_array(trim(BOTH '<>' from coalesce(p.Tags, '')), '><')) as UserTag
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    where p.Tags is not null
), CTE_BadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as TotalBadges,
        sum(case when utag.UserTag is not null then 1 else 0 end) as TagBasedBadgesForUserTags
    from Badges b
    left join RecursiveUserTags utag on utag.UserId = b.UserId and b.Name = utag.UserTag
    group by b.UserId, b.Class
), CTE_FirstPostPerUser as (
    select
      u.Id as UserId,
      min(p.CreationDate) as FirstQuestionDate,
      min(p2.CreationDate) as FirstAnswerDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    left join Posts p2 on p2.OwnerUserId = u.Id and p2.PostTypeId = 2
    group by u.Id
), CTE_UserVotesAskAnswers as (
    select
      u.Id as UserId,
      sum(vs_up.VisitsUpvote) as UpVotesQuestions,
      sum(vs_up.VisitsDownvote) as DownVotesQuestions,
      sum(ca.AverageAnswerScore) as AverageScoreAnswers,
      max(ca.MaxAnswerViewCount) as HighestViewCountAnswer
    from Users u
    left join lateral (
        select
          sum(case when vt.Name='UpMod' then 1 else 0 end) as VisitsUpvote,
          sum(case when vt.Name='DownMod' then 1 else 0 end) as VisitsDownvote
        from Posts pq
        left join Votes v on v.PostId = pq.Id
        left join VoteTypes vt on vt.Id = v.VoteTypeId
        where pq.OwnerUserId = u.Id
          and pq.PostTypeId = 1
    ) vs_up on true
    left join lateral (
        select avg(p.Score) as AverageAnswerScore, max(p.ViewCount) as MaxAnswerViewCount
        from Posts p
        where p.OwnerUserId = u.Id
          and p.PostTypeId = 2
    ) ca on true
    group by u.Id
), LeaderboardRanks as (
    select UserId, DisplayName,
      dense_rank() over (order by TopScore desc) as RankByTopQuestionScore,
      dense_rank() over (order by AvgAnswerScore desc NULLS LAST) as RankByAverageAnswer,
      dense_rank() over (order by UpVotesCount desc) as RankByUpvotesGiven
    from (
        select 
          u.Id as UserId,
          u.DisplayName,
          max(EntityQ.MaxQuestionScore) as TopScore,
          uva.AverageScoreUsersAnswers as AvgAnswerScore,
          uvaga.UpVotesGivenCount as UpVotesCount
        from Users u
        left join (
            select p.OwnerUserId, max(p.Score) as MaxQuestionScore
            from Posts p 
            where p.PostTypeId = 1
            group by p.OwnerUserId
        ) EntityQ on EntityQ.OwnerUserId = u.Id
        left join (
            select OwnerUserId, avg(Score) as AverageScoreUsersAnswers from Posts
            where PostTypeId = 2
            group by OwnerUserId
        ) uva on uva.OwnerUserId = u.Id
        left join (
            select UserId, count(*) as UpVotesGivenCount
            from Votes v
            join VoteTypes vt on vt.Id = v.VoteTypeId
            where vt.Name = 'UpMod'
            group by UserId
        ) uvaga on uvaga.UserId = u.Id
        group by u.Id, u.DisplayName, uva.AverageScoreUsersAnswers, uvaga.UpVotesGivenCount
    ) s        
)
select
    u.Id as UserId,
    u.DisplayName,
    coalesce(u.Reputation, 0) as Reputation,
    coalesce(cb.GoldBadges,0) as GoldBadges,
    coalesce(cb.SilverBadges,0) as SilverBadges,
    coalesce(cb.BronzeBadges,0) as BronzeBadges,
    subf.FirstQuestionDate as LastQuestionDate,
    subf.FirstAnswerDate
from Users u
left join (
    select
        UserId,
        sum(case when Class = 1 then TotalBadges else 0 end) as GoldBadges,
        sum(case when Class = 2 then TotalBadges else 0 end) as SilverBadges,
        sum(case when Class = 3 then TotalBadges else 0 end) as BronzeBadges
    from CTE_BadgeCounts
    group by UserId
) cb on cb.UserId = u.Id
left join CTE_FirstPostPerUser subf on subf.UserId = u.Id
left join CTE_UserVotesAskAnswers uv on uv.UserId = u.Id
left join LeaderboardRanks lr on lr.UserId = u.Id
order by u.Id;